import Foundation

/// ファイル切替・履歴適用の直後に走る「同期区間」(TASK-471)。
///
/// 表示中フォルダーの移動 → 選択の確定 → 一覧の取り直し、の 3 つは 1 かたまりで扱う
/// 必要がある。**この型が、その区間を書く唯一の場所。**
/// `SidebarNavigator.syncAfterSwitch` と `SidebarHistoryController` の履歴適用は
/// どちらもここを通る。かつては両者が同じ手順を別々に書いており、片方を直すと
/// 兄弟へ穴が残る形だった(そのことは後者のコメント自身が相互参照で記録していた)。
///
/// 型として切り出しているのは、`SidebarNavigator` のメソッドにすると
/// 「同期区間を書く場所」が navigator の 30 本を超えるメソッドの中に埋もれ、
/// 履歴側から借りている経路であることが読み取れなくなるため。
@MainActor
enum SidebarPostSwitchSync {
    /// 同期区間を適用する。
    ///
    /// **選択はこの区間で必ず確定する(TASK-445)。** 一覧の着地に委ねると
    /// 「currentDirectory だけが動いて選択は旧のまま」という部分適用が着地まで残り、
    /// 世代の追い越しやウィンドウ解放で着地しなければ永続する。旧選択がフォルダー行
    /// (または nil)だと `previewTarget` がその `.folder` のままになり、ファイル一覧が
    /// 本文に重なったまま戻らない。一覧に無い URL でも `matchingEntryURL` が生の URL を
    /// 返すため、着地を待たずに確定できる。
    ///
    /// 着地側でもう一度書くのは、確定した行が今の一覧に無い場合の上積み。一覧を取り直すと
    /// `DirectoryLister.appendingOpenFile` が開いている文書の行を補うため、列挙に載らない
    /// 拡張子のファイルでもそこで選択が行に当たるようになる。
    ///
    /// - Parameters:
    ///   - navigator: 移動と取り直しの経路を借りる先。
    ///   - directory: 表示中フォルダーの移動先。nil なら動かさない。書き換えを
    ///     `moveCurrentDirectory` の 1 経路に保つため、呼び出し側で
    ///     `currentDirectory` へ直接代入しないこと(TASK-465)。
    ///   - selection: 確定させる選択。nil は「選択なし」を意味する。
    ///   - refreshesWhenStaying: フォルダーを動かさないときも一覧を取り直すか。
    ///     動かしたときは指定によらず必ず取り直す(移動前の行が残るため)。
    static func apply(
        on navigator: SidebarNavigator,
        movingTo directory: URL?,
        selecting selection: URL?,
        refreshesWhenStaying: Bool
    ) {
        if let directory {
            navigator.moveCurrentDirectory(to: directory)
        }
        confirmSelection(selection, on: navigator)
        guard directory != nil || refreshesWhenStaying else { return }
        navigator.refreshFileList { [weak navigator] in
            guard let navigator else { return false }
            confirmSelection(selection, on: navigator)
            return true
        }
    }

    /// 選択をいまの一覧の行へ寄せて確定する。同期区間と一覧着地の両方から呼ぶ(冪等)。
    ///
    /// 書くのは渡された URL そのものだけで、「開いている文書の親フォルダー行を引く」
    /// といった推論は挟まない。推論に頼っていた頃は、引けなかったときに選択が nil や
    /// 一覧に無い生 URL になり、提示がフォルダー一覧へ落ちていた(TASK-468)。
    private static func confirmSelection(_ url: URL?, on navigator: SidebarNavigator) {
        navigator.fileListModel.selection = url.map {
            navigator.fileListModel.matchingEntryURL(for: $0)
        }
    }
}
