import AppKit

/// ネイティブタブバーの + と ⌘T を同じ生成経路へ送る。
final class ViewerDocumentWindow: NSWindow {
    override func newWindowForTab(_ sender: Any?) {
        AppDelegate.shared?.newWindowForTab(self)
    }
}
