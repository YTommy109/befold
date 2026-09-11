import Foundation

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
    /// プレゼン用のスライド窓で開く(TASK-593.2)。窓の再利用規則は `.newWindow` と同じ
    /// 「常に新規」で、器の違い(サイドバー無し・ツールバー無し)は窓の種別が決める。
    ///
    /// **修飾キーからは決して生成されない。** 下の初期化子(と、それへ委譲する
    /// BefoldRenderKit の `OpenDisposition(modifiers:)`)はリンククリックの修飾キーを
    /// 解釈するもので、この値はサイドバーのコンテキストメニューという明示的な
    /// 1 経路からしか渡らない(`OpenDispositionTests` が固定している)。
    case slide

    /// 修飾キーの押下状態からの解釈。cmd+shift > cmd > それ以外の順に判定する。
    /// ctrl はコンテキストメニュー扱いで呼び出し側が先に振り分けるため、ここでは無視する。
    ///
    /// **判定規則はこの初期化子だけが持つ。** AppKit のイベント(`NSEvent.ModifierFlags`)
    /// からの入口は BefoldRenderKit の `OpenDisposition+NSEvent.swift` にあり、
    /// そちらは真偽値へ落としてここへ委譲するだけの薄い変換に留める。
    /// BefoldKit を Foundation だけで成立する層に保つための配置
    /// (`scripts/check-befoldkit-platform-free.sh` が担保している)。
    public init(commandKey: Bool, shiftKey: Bool) {
        switch (commandKey, shiftKey) {
        case (true, true): self = .newWindow
        case (true, false): self = .newTab
        default: self = .currentTab
        }
    }
}
