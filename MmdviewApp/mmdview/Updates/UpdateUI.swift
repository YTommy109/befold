import AppKit

/// 更新関連の NSAlert 表示(GUI 層・自動テスト対象外)。
@MainActor
enum UpdateUI {
    /// 「更新あり」の通知。true なら「ダウンロードしてインストール」が選ばれた。
    static func askInstall(current: String, latest: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "mmdview \(displayVersion(latest)) が利用可能です"
        alert.informativeText = "現在のバージョンは v\(current) です。ダウンロードしてインストールしますか?"
        alert.addButton(withTitle: "ダウンロードしてインストール")
        alert.addButton(withTitle: "後で")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// ダウンロード完了の確認。true なら「インストールして再起動」が選ばれた。
    static func askRelaunch(latest: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(displayVersion(latest)) のダウンロードが完了しました"
        alert.informativeText = "インストールするとアプリが再起動します。"
        alert.addButton(withTitle: "インストールして再起動")
        alert.addButton(withTitle: "後で")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 開発ビルドでは自動インストールできないため、ブラウザへフォールバックする。
    static func presentDevBuildFallback(downloadURL: URL) {
        presentInfo(message: "開発ビルドのため自動インストールできません。ダウンロードページを開きます。")
        NSWorkspace.shared.open(downloadURL)
    }

    static func presentUpToDate(current: String) {
        presentInfo(message: "最新バージョンです(v\(current))")
    }

    static func presentCheckFailed() {
        presentInfo(message: "アップデートの確認に失敗しました。")
    }

    static func presentInstallFailed() {
        presentInfo(message: "アップデートのインストールに失敗しました。")
    }

    private static func displayVersion(_ version: String) -> String {
        version.hasPrefix("v") ? version : "v\(version)"
    }

    private static func presentInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
