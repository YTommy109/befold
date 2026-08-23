import Foundation

/// 絞り込み結果への窓口。**組み立ては `FileListSnapshot.make` が持ち**、ここは
/// モデルの状態(entries / entriesDirectory / listFilter)をそこへ渡すだけにする。
///
/// `listSnapshot` がこの一覧の唯一の入手経路で、`visibleEntries` も
/// `firstSelectableEntryURL` もここから導く。
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
        return FileListSnapshot.make(entries: entries, in: entriesDirectory, filter: listFilter)
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
