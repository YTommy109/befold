import Foundation

/// ダウンロード済み DMG からアプリを差し替えるための純粋ロジック。
/// 実際のマウント・スクリプト起動は UpdateFlowController が行う。
enum UpdateInstaller {
    enum InstallError: Error {
        /// `.app` バンドル外(開発ビルド)から実行されている。
        case notInstalledApp
        /// DMG 内に `.app` が見つからない。
        case appNotFoundInDMG
    }

    /// 実行中バンドルが差し替え対象の `.app` なら、その URL を返す。
    static func installedAppURL(bundleURL: URL) -> URL? {
        bundleURL.pathExtension == "app" ? bundleURL : nil
    }

    /// マウントポイント直下の `.app` バンドルを探す。
    static func findApp(inMountPoint mountPoint: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    /// アプリ終了後に差し替え・再起動を行うシェルスクリプトを生成する。
    /// 元プロセスの終了は PID ポーリングで待つ。
    static func updaterScript(
        appInDMG: String,
        installedApp: String,
        mountPoint: String,
        dmgPath: String,
        pid: Int32
    ) -> String {
        """
        #!/bin/bash
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "\(installedApp)"
        /bin/cp -R "\(appInDMG)" "\(installedApp)"
        /usr/bin/hdiutil detach "\(mountPoint)" -force
        /bin/rm -f "\(dmgPath)"
        /usr/bin/xattr -dr com.apple.quarantine "\(installedApp)" 2>/dev/null
        /usr/bin/open "\(installedApp)"
        /bin/rm -f "$0"
        """
    }
}
