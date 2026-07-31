import AppKit
import SwiftUI

/// Help > AI コーディングエージェント連携 ウィンドウ(単一インスタンス)。toggle() で開閉を切り替える。
@MainActor
final class AIIntegrationWindowController: NSWindowController {
    var isFrontmost: () -> Bool = { false }

    convenience init() {
        let hosting = NSHostingController(rootView: AIIntegrationView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "aiIntegration.windowTitle", bundle: .l10n)
        window.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable, NSWindow.StyleMask.resizable]
        window.setContentSize(NSSize(width: 480, height: 360))
        window.minSize = NSSize(width: 400, height: 300)
        self.init(window: window)
        isFrontmost = { [weak window] in window?.isKeyWindow ?? false }
    }

    func showAndActivate() {
        window?.center()
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if isFrontmost() {
            window?.close()
        } else {
            showAndActivate()
        }
    }
}
