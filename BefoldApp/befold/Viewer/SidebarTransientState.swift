import Foundation

/// サイドバーの「一時的な見せ方」。**窓ごとで、永続化しない**(TASK-585)。
///
/// `FileListModel` から分けているのは、この型が持つ値には**保存値の対がない**から。
/// 並び順・不可視ファイル・変更のみ・ツリー表示の 4 値は `SidebarDisplayDefaults` に
/// 「次に開く窓の出発点」を持ち、窓のライブ値はその写しとして始まる(ADR 0002「窓の状態」)。
/// 一方ここに載る絞り込みは、アプリを再起動すれば必ず初期値へ戻る。
/// 保存値の有無という既存の区分をそのまま型の境界にしてある。
@MainActor
@Observable
final class SidebarTransientState {
    /// ファイル名フィルターの検索文字列。フォルダ移動をまたいで保持する。
    var filterText: String = ""

    /// フィルターフィールドの開閉状態。true の間はヘッダー直下に検索欄を出す。
    var isFilterActive: Bool = false

    /// フィルター欄を閉じ、絞り込み文字列も解除する。
    /// アイコン再押下・esc のどちらからも同じ挙動にするための共通口。
    func closeFilter() {
        isFilterActive = false
        filterText = ""
    }
}
