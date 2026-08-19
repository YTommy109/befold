import Foundation

/// 絞り込み結果の導出。`FileListModel` 本体から分けているのは swiftlint の
/// file_length を超えないため。
///
/// **`listSnapshot` がこの一覧の唯一の作り方**で、`visibleEntries` も
/// `firstSelectableEntryURL` もここから導く。別々に `FileListFilter.apply` を
/// 呼ぶ形へ戻すと、同じ入力から違う答えが出る余地と、1 打鍵で絞り込みが何度も
/// 走る問題(TASK-418)が戻る。
extension FileListModel {
    /// フィルター適用後にサイドバーへ表示するエントリ。`entries`(ディスク由来の一覧)は
    /// 保持したまま、この算出側だけで絞り込む。
    /// git 変更での絞り込み(showChangedFilesOnly)も AND で併用する。
    var visibleEntries: [FileListEntry] {
        listSnapshot.visible
    }

    /// 絞り込みを 1 回だけ適用した結果。**同じ一覧を続けて何度も要る呼び出し側
    /// (キー操作・body 評価)は、`visibleEntries` を都度読まずにこれを 1 つ採って
    /// 使い回す**(TASK-418)。`FileListFilter.apply` は数千件のディレクトリでは
    /// 1 件ごとに WildcardMatcher を走らせるため、1 打鍵で何度も呼ぶと効く。
    var listSnapshot: FileListSnapshot {
        #if DEBUG
            snapshotEvaluations.note()
        #endif
        // 絞り込みだけを適用した一覧(祖先の足し戻し・開閉三角の確定を含まない)。
        // プレビューのフォルダー一覧へはこちらを渡す。祖先を足し戻した配列を渡すと、
        // 「条件に一致しないフォルダ」がプレビューにも現れる一方、同じフォルダを
        // 自前列挙する経路では消えるため、1 ウィンドウ内に絞り込みの答えが 2 つ並ぶ
        // (サイドバーとプレビューで答えを 1 つにする TASK-288 の巻き戻し)。
        let filtered = listFilter.apply(to: entries, in: entriesDirectory)
        // 順序が意味を持つ。祖先を足し戻してから開閉三角を確定させること。
        // 逆にすると、「名前は一致するが子が全部消えたフォルダ」の判定が、あとから
        // 足し戻した祖先を子として数えてしまう余地が残る。
        let visible = SidebarDisclosureResolver.resolving(
            SidebarTreeFilter.keepingAncestors(of: filtered, in: entries)
        )
        return FileListSnapshot(visible: visible, filtered: filtered)
    }

    /// フォルダーを降りた直後に選ぶ行の URL。一覧が空なら nil。
    ///
    /// 絞り込みは移動をまたいで残るので、`entries` ではなく実際に見えている
    /// 行から採る。ただし**一致した行を優先し、祖先として足し戻されただけの行
    /// (`SidebarTreeFilter`)は飛ばす**(TASK-406)。ツリー表示では一致行の祖先フォルダが
    /// 自分は一致しないまま残るので、見えている先頭をそのまま採ると絞り込みの答えでない行が
    /// 初期選択になり、探していた行まで矢印キーで降りることになる。一致行が 1 つも無い場合
    /// (祖先保持の性質上、通常は起こらない)だけ従来どおり先頭を採る(無選択へは落とさない)。
    var firstSelectableEntryURL: FileListEntry.ID? {
        listSnapshot.firstSelectable?.url
    }
}
