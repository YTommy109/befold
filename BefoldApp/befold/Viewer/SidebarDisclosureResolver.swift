import Foundation

/// 絞り込み後の行配列に対して、開閉三角の「見えている子が 0」を確定させる。
///
/// 行を組み立てる時点(SidebarRowBuilder)では、名前フィルタや「変更のみ表示」で
/// 何行消えるかがまだ分からない。絞り込みを通したあとの配列を 1 回走査して、
/// 展開済みなのに子行が 1 つも残っていないフォルダを
/// `.expandedEmpty(isFiltered: true)` へ落とす。
///
/// **「空のフォルダ」と「絞り込みで消えた」は別の状態**として区別する。前者は
/// 組み立て時点で子が 0 件だと分かっており(`.expandedEmpty(isFiltered: false)`)、
/// この関数は触らない。区別しないと、絞り込みを解除すれば見えるものを
/// 「空のフォルダ」と言い切ってしまう。
enum SidebarDisclosureResolver {
    /// 深さ優先で畳まれた配列なので、あるフォルダ行の子は直後に続く
    /// 「より深い行の連なり」の中にある。直接の子は depth がちょうど +1 のもの。
    static func resolving(_ rows: [FileListEntry]) -> [FileListEntry] {
        guard rows.contains(where: { $0.disclosure != nil }) else { return rows }
        return rows.enumerated().map { index, entry in
            guard entry.disclosure == .expanded else { return entry }
            return hasVisibleChild(of: entry, at: index, in: rows)
                ? entry
                : entry.disclosing(.expandedEmpty(isFiltered: true))
        }
    }

    private static func hasVisibleChild(
        of entry: FileListEntry, at index: Int, in rows: [FileListEntry]
    ) -> Bool {
        for row in rows[(index + 1)...] {
            // 同じ深さ以下へ戻ったら、このフォルダの配下は終わり。
            guard row.depth > entry.depth else { return false }
            if row.depth == entry.depth + 1 { return true }
        }
        return false
    }
}
