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

    /// 起動時の自動チェックからの案内。ユーザー操作を待たずに表示されるため、
    /// app-modal な `runModal()` は使わない(CLI 転送の ACK 待ちなど、他の main run loop
    /// 上の処理をブロックしてしまうため)。`window` があればそれに紐づく非ブロッキングな
    /// シートで表示し、表示できるウィンドウがない場合は案内自体を諦める(次回起動時に再チェックされる)。
    static func presentReinstallRecommended(attachedTo window: NSWindow?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "cli.install.reinstallRecommended", bundle: .l10n)
        alert.beginSheetModal(for: window)
    }

    private static func presentInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
