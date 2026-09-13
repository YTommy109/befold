import BefoldKit
import Foundation
import Testing

/// `BookmarkLibrary` の手動の並び(TASK-620.3)。`BookmarkLibraryTests` が `type_body_length` を
/// 超えたため、並びの規則だけをここへ分けた。
@Suite
struct BookmarkLibraryOrderTests {
    /// 並び替えは取り外して兄弟の直前へ入れる。兄弟が行き先に居なければ末尾(= 行き先の末尾)。
    @Test("move(before:) は同じ行き先の兄弟の直前へ入れ、兄弟が居なければ末尾へ入れる")
    func moveBeforeSiblingReorders() {
        let alpha = URL(fileURLWithPath: "/mock/a.md")
        let bravo = URL(fileURLWithPath: "/mock/b.md")
        let charlie = URL(fileURLWithPath: "/mock/c.md")
        var library = BookmarkLibrary(folders: [BookmarkFolder(path: ["Work"])])
        for url in [alpha, bravo, charlie] {
            library.add(url, isDirectory: false)
        }
        let order = { (folder: [String]) in library.children(of: folder).entries.map(\.displayName) }

        let moved1 = library.move(charlie, to: [], before: alpha)
        #expect(moved1)
        #expect(order([]) == ["c.md", "a.md", "b.md"])
        // 自分の直前 = 動かさない。
        let moved2 = library.move(alpha, to: [], before: alpha)
        #expect(moved2)
        #expect(order([]) == ["c.md", "a.md", "b.md"])
        // 別の階層へ。兄弟が行き先に居なければ末尾。
        let moved3 = library.move(alpha, to: ["Work"], before: bravo)
        #expect(moved3)
        let moved4 = library.move(bravo, to: ["Work"], before: alpha)
        #expect(moved4)
        #expect(order(["Work"]) == ["b.md", "a.md"])
        #expect(order([]) == ["c.md"])
        // before なし(メニューの「フォルダーへ移動」)も行き先の末尾。
        let moved5 = library.move(charlie, to: ["Work"])
        #expect(moved5)
        #expect(order(["Work"]) == ["b.md", "a.md", "c.md"])
        let moved6 = library.move(charlie, to: ["Missing"], before: alpha)
        #expect(!moved6)
    }

    /// 既存データ(手動の並びを知らない版が書いた値)は表示名順で見えていたので、その並びへ固定する。
    @Test("orderedManually は表示名順へ並べて印を付け、印の無い JSON は未移行として読める")
    func orderedManuallySortsByDisplayNameAndMarks() throws {
        let legacyJSON = """
        {"folders":[],"entries":[\
        {"path":"/mock/z.md","folder":[]},\
        {"path":"/mock/a.md","folder":[],"alias":"Zulu"},\
        {"path":"/mock/m.md","folder":[]}]}
        """
        let decoded = try JSONDecoder().decode(BookmarkLibrary.self, from: Data(legacyJSON.utf8))
        #expect(decoded.hasManualOrder == nil)
        #expect(BookmarkLibrary().hasManualOrder == true)

        let ordered = decoded.orderedManually()

        #expect(ordered.entries.map(\.displayName) == ["m.md", "z.md", "Zulu"])
        #expect(ordered.hasManualOrder == true)
    }
}
