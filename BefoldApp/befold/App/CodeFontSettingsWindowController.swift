import AppKit
import SwiftUI

/// フォント設定ウィンドウ(単一インスタンス)。既に開いていれば前面化するだけにする。
@MainActor
final class CodeFontSettingsWindowController: NSWindowController {
    convenience init(preference: CodeFontPreference, onChange: @escaping () -> Void) {
        let view = CodeFontSettingsView(preference: preference, onChange: onChange)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "settings.codeFont.windowTitle", bundle: .l10n)
        window.styleMask = [.titled, .closable]
        self.init(window: window)
    }

    func showAndActivate() {
        window?.center()
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
