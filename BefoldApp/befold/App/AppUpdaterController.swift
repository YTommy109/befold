import BefoldKit
import Foundation
import Sparkle

/// Sparkle 2 の updater の保持・起動と、フィード URL の解決。
///
/// `SPUStandardUpdaterController` は `updaterDelegate` を **weak** で持つ
/// (`Sparkle/SPUStandardUpdaterController.h`: "the updaterDelegate ... are weakly referenced,
/// so you are responsible for keeping them alive")。delegate はこの型自身なので、
/// **この型を AppDelegate が strong に保持し続けること**が生存条件になる。
@MainActor
final class AppUpdaterController: NSObject {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    /// 起動処理の最後に 1 回だけ呼ぶ。起動に失敗してもアプリは続行する(更新機能だけが無効になる)。
    func start() {
        #if DEBUG
            controller.updater.automaticallyChecksForUpdates = false
        #endif
        do {
            try controller.updater.start()
        } catch {
            NSLog("Sparkle updater failed to start: %@", error.localizedDescription)
        }
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    /// App > Check for Updates…
    func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}

// MARK: - SPUUpdaterDelegate

extension AppUpdaterController: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateChannel.read(from: .standard).feedURLString
    }
}
