import AppKit

/// ネイティブタブバーの + と ⌘T を同じ生成経路へ送る。
final class ViewerDocumentWindow: NSWindow {
    /// この空タブを置き換えた文書の窓。解決中だった別の要求が起点を読み替えるために読む。
    /// 窓に持つのは、閉じた空タブのコントローラは解放されるが、起点の窓は要求が保持し続けるため。
    weak var replacement: NSWindow?

    override func newWindowForTab(_ sender: Any?) {
        AppDelegate.shared?.newWindowForTab(self)
    }
}
