import AppKit

/// CLI インストール結果の NSAlert 表示(GUI 層・自動テスト対象外)。
@MainActor
enum CLIInstallUI {
    static func presentInstallSucceeded() {
        presentInfo(message: String(localized: "cli.install.success", bundle: .l10n))
    }

    static func presentInstallFailed() {
        presentInfo(message: String(localized: "cli.install.failed", bundle: .l10n))
    }

    private static func presentInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
