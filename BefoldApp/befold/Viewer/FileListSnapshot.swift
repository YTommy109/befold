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

    /// 指定した行の 1 つ上の階層にあたる行。無ければ nil。
    ///
    /// 判定に使うのは **配列上の depth の連なり**で、パス文字列の前置一致ではない。
    /// `visible` は深さ優先で並ぶ(SidebarRowBuilder)ため、対象より前にある
    /// 「depth がより小さい最後の行」が親にあたる。絞り込み中に祖先を足し戻す
    /// `SidebarTreeFilter.keepingAncestors` も同じ不変条件で動いており、判定源を
    /// 揃えておくと絞り込みの有無で答えが割れない。
    ///
    /// 最上位の行(depth 0。`..` を含む)には親が無いので nil を返す。ツリーの ← が
    /// ルートを変えないのはこの nil が `.ignored` になるからで、`..` を親として
    /// 返し始めると選択移動とルート移動が混ざる(TASK-408)。
    ///
    /// **`FileListModel` ではなくここに置くのが要点**(TASK-443)。モデル側に置くと
    /// 呼び出し側が手元のスナップショットを使えず `visibleEntries` を読み直すため、
    /// 「1 打鍵につき絞り込みは 1 回」(TASK-418)が ← キーの経路だけ破れる。
    func parent(of entryID: FileListEntry.ID) -> FileListEntry? {
        guard let index = visible.firstIndex(where: { $0.id == entryID }) else { return nil }
        let depth = visible[index].depth
        guard depth > 0 else { return nil }
        return visible[..<index].last { $0.depth < depth }
    }

    /// いま見えている行の中での位置。選択が無い・隠れているなら nil。
    ///
    /// 選択行のスクロール追従(`FileListModel`)もここを使う。List は `visible` を
    /// 1 セクションでそのまま描くため、この添字が NSTableView の行番号と一致する。
    func index(of selection: FileListEntry.ID?) -> Int? {
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
