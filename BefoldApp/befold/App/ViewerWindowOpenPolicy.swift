import AppKit
import BefoldKit

/// 窓を開くときの**純粋な判定**。副作用を持たず、`ViewerWindowManager` の状態も引かない
/// (候補や記憶は引数で受ける)。openViewer の経路から規則だけを切り出したもの。
enum ViewerWindowOpenPolicy {
    /// 同じファイルを表示中の候補から、再利用できるコントローラを選ぶ(nil なら新規に開く)。
    ///
    /// - `.currentTab`: Finder/CLI/リンクからの再オープン。どのウィンドウで開いていても
    ///   既存を前面化する(ウィンドウ内のサイドバー切替だけは openViewer を通らず
    ///   自ウィンドウを切り替える)。
    /// - `.newTab`: cmd+クリック等。起点ウィンドウと同じタブグループに同じファイルの
    ///   タブが既にあればそれを選択し、重複タブを作らない(TASK-487)。別ウィンドウで
    ///   開いているだけなら素通しし、起点のタブグループへ新しいタブを開く。
    /// - `.newWindow` / `.slide`: ユーザーが明示的に新しい窓を求めた経路なので常に素通しする
    ///   (既に開いているファイルで「新しいウィンドウで開く」が無反応に見える問題: issue #431)。
    ///   スライド窓は器が違うだけで、再利用の規則は `.newWindow` と同じ。
    @MainActor
    static func reusableController(
        from candidates: [ViewerWindowController],
        disposition: OpenDisposition,
        relativeTo sourceWindow: NSWindow?
    ) -> ViewerWindowController? {
        switch disposition {
        case .currentTab:
            return candidates.first
        case .newTab:
            guard let sourceWindow else { return nil }
            let siblings = ViewerTabGrouping.tabWindows(of: sourceWindow)
            return candidates.first { controller in
                guard let window = controller.window else { return false }
                return siblings.contains(window)
            }
        case .newWindow, .slide:
            return nil
        }
    }

    /// 新規ウィンドウのサイドバー初期開閉状態。
    ///
    /// 解決順: 種別 > CLI の明示指定(`--sidebar`/`--no-sidebar`) > フォルダーオープンに
    /// よる強制表示 > 記憶の引き継ぎ。
    ///
    /// **サイドバーを持たない種別は記憶を読まない**(TASK-593.2)。畳んでいることは種別の
    /// 帰結であって利用者の選択ではない(ADR 0002「窓の状態」)。`remembered` を
    /// `@autoclosure` で受けているのがその短絡の担保。
    static func initialSidebarCollapsed(
        kind: ViewerWindowKind,
        showSidebar: Bool?,
        forceSidebarVisible: Bool,
        remembered: @autoclosure () -> Bool
    ) -> Bool {
        guard kind.allowsSidebar else { return true }
        if let showSidebar { return !showSidebar }
        if forceSidebarVisible { return false }
        return remembered()
    }
}
