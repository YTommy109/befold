import AppKit

/// ネイティブタブバーの + と ⌘T を同じ生成経路へ送る。
final class ViewerDocumentWindow: NSWindow {
    /// 単独の窓でもタブを掴めるようにする。切り離し後もキー化の契機で復帰する。
    override func becomeKey() {
        super.becomeKey()
        if tabbingMode != .disallowed, tabGroup?.isTabBarVisible != true {
            toggleTabBar(nil)
        }
    }

    override func newWindowForTab(_ sender: Any?) {
        AppDelegate.shared?.newWindowForTab(self)
    }
}
