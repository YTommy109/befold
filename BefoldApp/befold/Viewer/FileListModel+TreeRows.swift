import Foundation

/// ツリー表示で、行どうしの親子関係を `visibleEntries` の並びから読む部分。
/// FileListModel 本体から分けているのは、swiftlint の file_length を超えないようにするため
/// (`SidebarNavigator+History` などと同じ理由)。
extension FileListModel {
    /// 指定した行の 1 つ上の階層にあたる行。無ければ nil。
    ///
    /// 判定に使うのは **配列上の depth の連なり**で、パス文字列の前置一致ではない。
    /// `visibleEntries` は深さ優先で並ぶ(SidebarRowBuilder)ため、対象より前にある
    /// 「depth がより小さい最後の行」が親にあたる。絞り込み中に祖先を足し戻す
    /// `SidebarTreeFilter.keepingAncestors` も同じ不変条件で動いており、判定源を
    /// 揃えておくと絞り込みの有無で答えが割れない。
    ///
    /// 最上位の行(depth 0。`..` を含む)には親が無いので nil を返す。ツリーの ← が
    /// ルートを変えないのはこの nil が `.ignored` になるからで、`..` を親として
    /// 返し始めると選択移動とルート移動が混ざる(TASK-408)。
    func parentRow(of entryID: FileListEntry.ID) -> FileListEntry? {
        // 計算プロパティなので 1 回だけ束縛する(添字探索と深さ走査で 2 回作らない)。
        let rows = visibleEntries
        guard let index = rows.firstIndex(where: { $0.id == entryID }) else { return nil }
        let depth = rows[index].depth
        guard depth > 0 else { return nil }
        return rows[..<index].last { $0.depth < depth }
    }
}
