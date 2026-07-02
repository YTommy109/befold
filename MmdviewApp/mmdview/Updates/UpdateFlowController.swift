import AppKit

/// 「更新あり」以降のダウンロード→確認→インストールを担うフロー(GUI 層・自動テスト対象外)。
@MainActor
final class UpdateFlowController {
    private(set) var isRunning = false

    /// 更新フローを開始する。多重起動は無視する。
    func run(current: String, latest: String, downloadURL: URL) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        guard UpdateUI.askInstall(current: current, latest: latest) else { return }
        guard let installedApp = UpdateInstaller.installedAppURL(bundleURL: Bundle.main.bundleURL)
        else {
            UpdateUI.presentDevBuildFallback(downloadURL: downloadURL)
            return
        }

        let dmgURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-update.dmg")
        let progressWindow = DownloadProgressWindowController()
        progressWindow.showWindow(nil)
        do {
            try await UpdateDownloader().download(from: downloadURL, to: dmgURL) { value in
                Task { @MainActor in
                    progressWindow.setProgress(value)
                }
            }
            progressWindow.close()
            guard UpdateUI.askRelaunch(latest: latest) else { return }
            try await installAndRelaunch(dmgAt: dmgURL, installedApp: installedApp)
        } catch {
            progressWindow.close()
            UpdateUI.presentInstallFailed()
        }
    }

    /// DMG をマウントしてアップデータスクリプトを起動し、アプリを終了する。
    /// 成功時はプロセスが終了するため戻らない。
    private func installAndRelaunch(dmgAt dmgURL: URL, installedApp: URL) async throws {
        let mounter = DMGMounter()
        let mountPoint = try await Task.detached { try mounter.mount(dmgAt: dmgURL) }.value
        guard let appInDMG = UpdateInstaller.findApp(inMountPoint: mountPoint) else {
            await Task.detached { mounter.detach(mountPoint: mountPoint) }.value
            throw UpdateInstaller.InstallError.appNotFoundInDMG
        }

        let script = UpdateInstaller.updaterScript(
            appInDMG: appInDMG.path,
            installedApp: installedApp.path,
            mountPoint: mountPoint.path,
            dmgPath: dmgURL.path,
            pid: ProcessInfo.processInfo.processIdentifier)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-updater.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
        exit(0)
    }
}
