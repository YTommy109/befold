import AppKit
import BefoldKit

/// AppKit のイベントから `OpenDisposition` を作る入口(TASK-594)。
///
/// **判定規則はここに持たない。** 修飾キーと開き方の対応表は BefoldKit の
/// `OpenDisposition(commandKey:shiftKey:)` 1 つに閉じており、ここは
/// `NSEvent.ModifierFlags` を真偽値へ落とすだけの変換に留める。ここに条件を足すと、
/// JS ブリッジ経由のクリック(生の真偽値が届く)と AppKit 経由のクリックで
/// 対応表が二重化する。
///
/// BefoldKit ではなくこの層に置くのは、BefoldKit をプラットフォーム非依存
/// (Foundation のみ)に保つため。呼び出し元は同じターゲットの
/// `DirectHTMLLinkPolicy` と、上位の befold の `FileListView` の 2 箇所で、
/// 依存が befold → BefoldRenderKit → BefoldKit の一方向なので、両方から見える
/// 最下層がここになる。
public extension OpenDisposition {
    /// AppKit のイベントからの解釈。
    init(modifiers: NSEvent.ModifierFlags) {
        self.init(commandKey: modifiers.contains(.command), shiftKey: modifiers.contains(.shift))
    }
}
