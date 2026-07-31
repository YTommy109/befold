import AppKit
import SwiftUI

/// About ウィンドウ(単一インスタンス)。toggle() で開閉を切り替える。
@MainActor
final class AboutWindowController: NSWindowController {
    /// 最前面判定のシーム。既定は実ウィンドウの isKeyWindow だが、テストから注入できるようにする。
    var isFrontmost: () -> Bool = { false }

    convenience init() {
        let view = AboutView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "about.windowTitle", bundle: .l10n)
        window.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable]
        window.setContentSize(NSSize(width: 480, height: 340))
        window.minSize = NSSize(width: 360, height: 260)
        self.init(window: window)
        isFrontmost = { [weak window] in window?.isKeyWindow ?? false }
    }

    func showAndActivate() {
        window?.center()
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// 最前面なら閉じ、そうでなければ開く/前面化する。
    func toggle() {
        if isFrontmost() {
            window?.close()
        } else {
            showAndActivate()
        }
    }
}
