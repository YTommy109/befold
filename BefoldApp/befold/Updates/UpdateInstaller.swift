import Foundation

/// ダウンロード済み DMG からアプリを差し替えるための純粋ロジック。
/// 実際のマウント・スクリプト起動は UpdateFlowController が行う。
enum UpdateInstaller {
    enum InstallError: Error {
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
            at: mountPoint, includingPropertiesForKeys: nil
        )) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    /// アプリ終了後に差し替え・再起動を行うシェルスクリプトを生成する。
    /// 元プロセスの終了は PID ポーリングで待つ。
    /// 新アプリはまずステージング(`<installedApp>.update`)へコピーし、
    /// 成功した場合のみ旧アプリを削除して入れ替える(コピー失敗でアプリが消滅しないように)。
    /// 全出力は logPath へ追記し、失敗を事後調査できるようにする。
    static func updaterScript(
        appInDMG: String,
        installedApp: String,
        mountPoint: String,
        dmgPath: String,
        pid: Int32,
        logPath: String
    ) -> String {
        // パスはすべて shellQuoted でシングルクォート化してから埋め込む。
        // ダブルクォートだと `"` `$` バッククォートを含むパスでスクリプトが破損・
        // インジェクションされる余地があるため。
        let staging = (installedApp + ".update").shellQuoted
        let installedApp = installedApp.shellQuoted
        let appInDMG = appInDMG.shellQuoted
        let mountPoint = mountPoint.shellQuoted
        let dmgPath = dmgPath.shellQuoted
        let logPath = logPath.shellQuoted
        return """
        #!/bin/bash
        exec >> \(logPath) 2>&1
        echo "=== $(/bin/date '+%Y-%m-%dT%H:%M:%S%z') updater start (waiting for pid \(pid))"
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf \(staging)
        if /bin/cp -R \(appInDMG) \(staging); then
            /bin/rm -rf \(installedApp)
            /bin/mv \(staging) \(installedApp)
            echo "install ok"
        else
            echo "ERROR: copy failed; keeping installed app"
            /bin/rm -rf \(staging)
        fi
        /usr/bin/hdiutil detach \(mountPoint) -force
        /bin/rm -f \(dmgPath)
        /usr/bin/xattr -dr com.apple.quarantine \(installedApp)
        /usr/bin/open \(installedApp)
        echo "=== $(/bin/date '+%Y-%m-%dT%H:%M:%S%z') updater done"
        /bin/rm -f "$0"
        """
    }
}
