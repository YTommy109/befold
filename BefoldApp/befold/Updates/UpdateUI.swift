import AppKit

/// 更新関連の NSAlert 表示(GUI 層・自動テスト対象外)。
@MainActor
enum UpdateUI {
    /// 「更新あり」の通知。true なら「ダウンロードしてインストール」が選ばれた。
    static func askInstall(current: String, latest: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(
            format: String(localized: "update.available.title", bundle: .l10n),
            displayVersion(latest)
        )
        alert.informativeText = String(
            format: String(localized: "update.available.message", bundle: .l10n),
            current
        )
        alert.addButton(withTitle: String(localized: "update.available.install", bundle: .l10n))
        alert.addButton(withTitle: String(localized: "update.later", bundle: .l10n))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// ダウンロード完了の確認。true なら「インストールして再起動」が選ばれた。
    static func askRelaunch(latest: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(
            format: String(localized: "update.downloaded.title", bundle: .l10n),
            displayVersion(latest)
        )
        alert.informativeText = String(localized: "update.downloaded.message", bundle: .l10n)
        alert.addButton(withTitle: String(localized: "update.downloaded.installAndRelaunch", bundle: .l10n))
        alert.addButton(withTitle: String(localized: "update.later", bundle: .l10n))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 開発ビルドでは自動インストールできないため、ブラウザへフォールバックする。
    static func presentDevBuildFallback(downloadURL: URL) {
        presentInfo(message: String(localized: "update.devBuildFallback", bundle: .l10n))
        NSWorkspace.shared.open(downloadURL)
    }

    static func presentUpToDate(current: String) {
        presentInfo(message: String(
            format: String(localized: "update.upToDate", bundle: .l10n),
            current
        ))
    }

    static func presentCheckFailed() {
        presentInfo(message: String(localized: "update.checkFailed", bundle: .l10n))
    }

    static func presentInstallFailed() {
        presentInfo(message: String(localized: "update.installFailed", bundle: .l10n))
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
