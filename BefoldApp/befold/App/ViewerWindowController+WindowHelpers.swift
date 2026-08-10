import AppKit

// MARK: - Window / Content Helpers

extension ViewerWindowController {
    /// ウィンドウのタイトルと representedURL を新しい URL に合わせて更新する。
    /// handleRename / switchFile 共通の表示更新。現在 URL 自体は store が保持するため
    /// ここでは複製・代入せず、ウィンドウの見た目だけを追従させる。
    func applyURLToWindow(_ newURL: URL) {
        guard let window else { return }
        window.title = newURL.lastPathComponent
        window.representedURL = newURL
    }

    /// 既存のビューアウィンドウと位置が完全に一致する場合だけ、標準のカスケード量ずらす。
    /// cascadeTopLeft(from:) は移動先を戻り値で返すため、戻り値を自分に適用する。
    /// ずらした先が別ウィンドウと一致することがあるので、重ならなくなるまで繰り返す。
    func offsetFrameToAvoidOverlap(_ window: NSWindow) {
        func overlapsExisting() -> Bool {
            NSApp.windows.contains { other in
                other !== window
                    && other.isVisible
                    && other.windowController is ViewerWindowController
                    && other.frame.origin == window.frame.origin
            }
        }
        var attempts = 0
        while overlapsExisting(), attempts < 20 {
            let shifted = window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
            window.setFrameTopLeftPoint(shifted)
            attempts += 1
        }
    }
}
