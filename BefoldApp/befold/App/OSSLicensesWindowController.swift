import AppKit
import SwiftUI

/// Help > OSS 謝辞 ウィンドウ(単一インスタンス)。toggle() で開閉を切り替える。
@MainActor
final class OSSLicensesWindowController: NSWindowController {
    var isFrontmost: () -> Bool = { false }

    convenience init() {
        let hosting = NSHostingController(rootView: OSSLicensesView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "ossLicenses.windowTitle", bundle: .l10n)
        window.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable, NSWindow.StyleMask.resizable]
        window.setContentSize(NSSize(width: 560, height: 560))
        window.minSize = NSSize(width: 420, height: 320)
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
