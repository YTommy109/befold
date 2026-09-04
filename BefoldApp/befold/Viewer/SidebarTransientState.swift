import Foundation

/// サイドバーの「一時的な見せ方」。**窓ごとで、永続化しない**(TASK-585)。
///
/// `FileListModel` から分けているのは、この型が持つ値には**保存値の対がない**から。
/// 並び順・不可視ファイル・変更のみ・ツリー表示の 4 値は `SidebarDisplayDefaults` に
/// 「次に開く窓の出発点」を持ち、窓のライブ値はその写しとして始まる(ADR 0002「窓の状態」)。
/// 一方ここに載る絞り込みとスライドモードは、アプリを再起動すれば必ず初期値へ戻る。
/// 保存値の有無という既存の区分をそのまま型の境界にしてある。
///
/// スライドモードの真値はここ 1 つだけ。`ViewerSplitViewController` は幅だけを持ち、
/// 真偽値を二重に持たない(二重に持つと幅と表示が食い違う形が作れてしまう)。
@MainActor
@Observable
final class SidebarTransientState {
    /// ファイル名フィルターの検索文字列。フォルダ移動をまたいで保持する。
    var filterText: String = ""

    /// フィルターフィールドの開閉状態。true の間はヘッダー直下に検索欄を出す。
    var isFilterActive: Bool = false

    /// プレゼン用のスライドモード。変更は `setSlideMode(_:)` を通すこと
    /// (直接代入するとフィルターが閉じない)。出入りの手順は `SlideModeCoordinator`。
    private(set) var isSlideMode = false

    /// スライドモードの出入り。**進入時にフィルターを閉じる。**
    /// ヘッダーが入力欄ごとアイコン 1 つへ置き換わるため、絞り込みだけが残ると
    /// 細い一覧が「なぜこれだけなのか」分からなくなる。
    func setSlideMode(_ enabled: Bool) {
        guard isSlideMode != enabled else { return }
        isSlideMode = enabled
        if enabled { closeFilter() }
    }

    /// フィルター欄を閉じ、絞り込み文字列も解除する。
    /// アイコン再押下・esc・スライドモード進入のどれからも同じ挙動にするための共通口。
    func closeFilter() {
        isFilterActive = false
        filterText = ""
    }
}
