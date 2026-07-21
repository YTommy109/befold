import AppKit
import UserNotifications

/// CLI インストール結果の通知表示(GUI 層・自動テスト対象外)。
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
    /// 上の処理をブロックしてしまうため)。また、ウィンドウに紐づくシートだと表示できる
    /// 可視ウィンドウが1つも無い起動直後(セッション復元対象なし・ファイル指定なし)には
    /// 表示先を失って案内が消えてしまうため、ウィンドウの有無に依存しない通知センターの
    /// バナー通知として表示する。
    static func presentReinstallRecommended() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        let content = UNMutableNotificationContent()
        content.title = "befold"
        content.body = String(localized: "cli.install.reinstallRecommended", bundle: .l10n)
        let request = UNNotificationRequest(
            identifier: "cli.install.reinstallRecommended", content: content, trigger: nil
        )
        try? await center.add(request)
    }

    private static func presentInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
