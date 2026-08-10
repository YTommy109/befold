import Foundation

/// 絞り込みを 1 回だけ適用した結果のスナップショット。
///
/// サイドバーの 1 回のキー操作は、選択中の行の判定・移動先の決定・親行の探索と
/// 同じ一覧を何度も要る。これを `FileListModel.visibleEntries` の再評価で賄うと、
/// 1 打鍵ごとに `FileListFilter.apply`(数千件なら 1 件ずつ WildcardMatcher)が
/// 何度も走る。呼び出し側は先頭でこの型を 1 つ作り、以降は引数で渡す。
///
/// `matchedIDs` を一緒に持つのが要点。「絞り込みの先頭行」は
/// 「見えている先頭」ではなく「**自分自身が条件に一致した**行のうち先頭」であり
/// (TASK-406)、その判定には祖先として足し戻された行を見分ける情報が要る。
/// 一致集合を `visible` と別々に採ると絞り込みが 2 回走るうえ、両者が別の入力を
/// 読む余地が残る。
struct FileListSnapshot {
    /// サイドバーへ実際に並べる行。祖先の足し戻し・開閉三角の確定まで済んでいる。
    let visible: [FileListEntry]
    /// 絞り込みだけを適用した一覧(祖先の足し戻し・開閉三角の確定を含まない)。
    /// プレビューのフォルダー一覧へはこちらを渡す。
    let filtered: [FileListEntry]
    /// 自分自身が絞り込み条件に一致した行の ID。祖先として足し戻されただけの行は含まない。
    let matchedIDs: Set<FileListEntry.ID>

    init(visible: [FileListEntry], filtered: [FileListEntry]) {
        self.visible = visible
        self.filtered = filtered
        matchedIDs = Set(filtered.map(\.id))
    }

    /// 選択の移動先になりうる行。`.parentNavigation` は上位フォルダーへの移動手段で
    /// あって一覧の項目ではないため除く。
    private var selectableEntries: [FileListEntry] {
        visible.filter { $0.kind != .parentNavigation }
    }

    /// 絞り込み結果の先頭。一致行を優先し、祖先として足し戻されただけの行は飛ばす
    /// (TASK-406)。一致行が 1 つも無い場合だけ見えている先頭を採る。
    var firstSelectable: FileListEntry? {
        let selectable = selectableEntries
        return selectable.first { matchedIDs.contains($0.id) } ?? selectable.first
    }

    /// 絞り込み結果の末尾。`firstSelectable` と対称に決める。
    var lastSelectable: FileListEntry? {
        let selectable = selectableEntries
        return selectable.last { matchedIDs.contains($0.id) } ?? selectable.last
    }

    /// `selection` の次の行。行き先が無ければ nil。
    ///
    /// **選択が無い場合と、絞り込みで選択行が隠れている場合は同じ扱い**にして
    /// 絞り込み結果の先頭を返す。両者を分けて後者を「行き先なし」にすると、
    /// 開いているファイルに一致しないパターンを打った時点でキーボードから
    /// 絞り込み結果へ到達できなくなる(TASK-418)。
    func next(after selection: FileListEntry.ID?) -> FileListEntry? {
        guard let index = index(of: selection) else { return firstSelectable }
        guard index + 1 < visible.count else { return nil }
        return visible[index + 1]
    }

    /// `selection` の前の行。行き先が無ければ nil。
    /// 選択が無い・隠れている場合は絞り込み結果の末尾を返す(`next` と対称)。
    func previous(before selection: FileListEntry.ID?) -> FileListEntry? {
        guard let index = index(of: selection) else { return lastSelectable }
        guard index > 0 else { return nil }
        return visible[index - 1]
    }

    /// いま見えている行の中での位置。選択が無い・隠れているなら nil。
    private func index(of selection: FileListEntry.ID?) -> Int? {
        guard let selection else { return nil }
        return visible.firstIndex { $0.id == selection }
    }

    /// `selection` に対応する見えている行。隠れていれば nil。
    func entry(for selection: FileListEntry.ID?) -> FileListEntry? {
        guard let index = index(of: selection) else { return nil }
        return visible[index]
    }

    /// 上位フォルダーへの移動行(`..`)。絞り込みに関わらず常に残る。
    var parentNavigationEntry: FileListEntry? {
        visible.first { $0.kind == .parentNavigation }
    }
}
