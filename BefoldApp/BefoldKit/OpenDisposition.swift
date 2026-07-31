import AppKit

/// リンクのアクティベーションに対する「開き方」。
/// 修飾キーからの解釈をここ 1 箇所に集約し、JS ブリッジ経由のクリックと
/// 直接 HTML モードの decidePolicyFor が同じ対応表を通るようにする。
public enum OpenDisposition: Equatable, Sendable {
    /// 今のウィンドウで表示を差し替える。
    case currentTab
    /// 同じウィンドウのタブグループへ追加し、そのタブを前面にする。
    case newTab
    /// 新規ウィンドウで開く。
    case newWindow

    /// 修飾キーの押下状態からの解釈。cmd+shift > cmd > それ以外の順に判定する。
    /// ctrl はコンテキストメニュー扱いで呼び出し側が先に振り分けるため、ここでは無視する。
    public init(commandKey: Bool, shiftKey: Bool) {
        switch (commandKey, shiftKey) {
        case (true, true): self = .newWindow
        case (true, false): self = .newTab
        default: self = .currentTab
        }
    }

    /// AppKit のイベントからの解釈。JS 側は生の真偽値を送ってくるため入口が 2 つあるが、
    /// 判定規則そのものは commandKey/shiftKey の初期化子 1 つに閉じる。
    public init(modifiers: NSEvent.ModifierFlags) {
        self.init(commandKey: modifiers.contains(.command), shiftKey: modifiers.contains(.shift))
    }
}
