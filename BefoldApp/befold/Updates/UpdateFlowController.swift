import AppKit

/// アップデータスクリプトの書き出しと起動を抽象化するプロトコル。
protocol UpdaterScriptLaunching: Sendable {
    func launch(script: String) throws
}

/// アップデータスクリプトを一時ファイルに書き出して /bin/bash で起動する。
struct UpdaterScriptLauncher: UpdaterScriptLaunching {
    func launch(script: String) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("befold-updater-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
    }
}

/// 「更新あり」以降のダウンロード→確認→インストールを担うフロー(GUI 層・自動テスト対象外)。
@MainActor
final class UpdateFlowController {
    private(set) var isRunning = false
    private let downloader: any UpdateDownloading
    private let mounter: any DMGMounting
    private let scriptLauncher: any UpdaterScriptLaunching
    private let makeProgressWindow: @MainActor () -> DownloadProgressWindowController

    init(
        downloader: any UpdateDownloading = UpdateDownloader(),
        mounter: any DMGMounting = DMGMounter(),
        scriptLauncher: any UpdaterScriptLaunching = UpdaterScriptLauncher(),
        makeProgressWindow: @escaping @MainActor () -> DownloadProgressWindowController = {
            DownloadProgressWindowController()
        }
    ) {
        self.downloader = downloader
        self.mounter = mounter
        self.scriptLauncher = scriptLauncher
        self.makeProgressWindow = makeProgressWindow
    }

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
            .appendingPathComponent("befold-update-\(UUID().uuidString).dmg")
        let progressWindow = makeProgressWindow()
        progressWindow.showWindow(nil)
        do {
            try await downloader.download(from: downloadURL, to: dmgURL) { value in
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
        let mounter = mounter
        let mountPoint = try await Task.detached { try mounter.mount(dmgAt: dmgURL) }.value
        guard let appInDMG = UpdateInstaller.findApp(inMountPoint: mountPoint) else {
            await Task.detached { mounter.detach(mountPoint: mountPoint) }.value
            throw UpdateInstaller.InstallError.appNotFoundInDMG
        }

        // 署名検証: ダウンロードしたアプリが実行中アプリと同一の Team ID で
        // 有効に署名されていることを確認する。検証失敗時はインストールを中断する。
        do {
            try CodeSignatureVerifier.verify(appAt: appInDMG)
        } catch {
            await Task.detached { mounter.detach(mountPoint: mountPoint) }.value
            throw error
        }

        let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/befold-updater.log")
        let script = UpdateInstaller.updaterScript(
            appInDMG: appInDMG.path,
            installedApp: installedApp.path,
            mountPoint: mountPoint.path,
            dmgPath: dmgURL.path,
            pid: ProcessInfo.processInfo.processIdentifier,
            logPath: logURL.path
        )
        try scriptLauncher.launch(script: script)
        exit(0)
    }
}
