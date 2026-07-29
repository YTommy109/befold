import AppKit
import SwiftUI

/// フォント設定ウィンドウ(単一インスタンス)。toggle() で開閉を切り替える。
@MainActor
final class CodeFontSettingsWindowController: NSWindowController {
    /// 最前面判定のシーム。既定は実ウィンドウの isKeyWindow だが、テストから注入できるようにする。
    var isFrontmost: () -> Bool = { false }

    convenience init(preference: CodeFontPreference, onChange: @escaping () -> Void) {
        let view = CodeFontSettingsView(preference: preference, onChange: onChange)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "settings.windowTitle", bundle: .l10n)
        window.styleMask = [.titled, .closable]
        self.init(window: window)
        isFrontmost = { [weak window] in window?.isKeyWindow ?? false }
    }

    func showAndActivate() {
        window?.center()
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// 最前面なら閉じ、そうでなければ開く/前面化する(⌘, の再押下で引っ込む)。
    func toggle() {
        if isFrontmost() {
            window?.close()
        } else {
            showAndActivate()
        }
    }
}
