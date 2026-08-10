import Foundation

/// 絞り込みで残った行の**祖先**を足し戻す。
///
/// `FileListFilter` はフラットな配列に一様に効くため、ツリー展開した行配列に
/// そのまま掛けると **親フォルダ行だけが消えて子行が残る**。インデントだけが
/// 存在しない親を指す孤児行になるので、残った行の祖先は自分が条件に一致しなくても
/// 残す。
///
/// **`FileListFilter` 側には入れない。** あちらはサイドバーとプレビュー内の
/// フォルダー一覧が共有する型で、プレビューは 1 階層ぶんのフラットな一覧しか
/// 持たない。祖先の概念が無い場所へ祖先保持を持ち込むと、共有の意味が壊れる。
///
/// - Note: **祖先は「配列上の depth の連なり」で決める。pathKey の前置一致では
///   決めない。** 行の組み立て(`SidebarRowBuilder`)はシンボリックリンク越しの
///   循環を止めるために訪問済みキーで枝を打ち切るので、パス文字列の親子関係と
///   実際に並んでいる行の親子関係は一致が保証されない。同じ名前のフォルダが
///   別の階層に並ぶ場合も、前置一致では取り違える。
enum SidebarTreeFilter {
    /// - Parameters:
    ///   - filtered: 絞り込み後の行(元の順序を保っていること)。
    ///   - rows: 絞り込み前の行。深さ優先で畳まれた並びであること。
    static func keepingAncestors(
        of filtered: [FileListEntry], in rows: [FileListEntry]
    ) -> [FileListEntry] {
        // 素通しになる条件は「なるはず」ではなくコード上の分岐で担保する。
        // ここは body 評価・キー操作のたびに走る経路にある。
        guard filtered.count != rows.count else { return filtered }
        guard rows.contains(where: { $0.depth > 0 }) else { return filtered }

        let survivors = Set(filtered.map(\.id))
        var keep = survivors
        // 深さ優先で畳まれた配列なので、ある行の祖先は「それより前にある、より浅い
        // 最初の行」を depth 0 まで辿ったもの。前から走査しながら各深さの直近の行を
        // 覚えておけば、残った行に出会った時点でその鎖をそのまま拾える。
        var ancestorAtDepth: [Int: FileListEntry.ID] = [:]
        var chain: [FileListEntry.ID] = []
        for row in rows {
            ancestorAtDepth[row.depth] = row.id
            guard survivors.contains(row.id), row.depth > 0 else { continue }
            chain.removeAll(keepingCapacity: true)
            for depth in 0 ..< row.depth {
                guard let ancestor = ancestorAtDepth[depth] else { continue }
                chain.append(ancestor)
            }
            keep.formUnion(chain)
        }
        guard keep.count != survivors.count else { return filtered }
        return rows.filter { keep.contains($0.id) }
    }
}
