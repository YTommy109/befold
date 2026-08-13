@testable import befold
import Foundation
import Testing

/// ツリー展開時の絞り込みの意味(TASK-361.5)。
///
/// 採用したのは「展開済みの階層だけを絞る + 残った行の祖先は保持する」。
/// 未展開フォルダの自動展開(一致する子を持つ祖先を探して開く)は採らない。
@Suite
struct SidebarTreeFilterTests {
    private func folder(_ path: String, depth: Int) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .folder).indented(to: depth)
    }

    private func file(_ path: String, depth: Int) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .file).indented(to: depth)
    }

    /// 祖先を残さないと、インデントだけが残って存在しない親を指す孤児行になる。
    @Test("一致した子の祖先フォルダは、自分が一致しなくても残る")
    func keepsAncestorsOfMatchingRows() {
        let rows = [folder("/a", depth: 0), file("/a/note.md", depth: 1)]
        let filtered = [rows[1]]

        let result = SidebarTreeFilter.keepingAncestors(of: filtered, in: rows)

        #expect(result.map(\.url.lastPathComponent) == ["a", "note.md"])
    }

    @Test("入れ子の祖先はルートまで辿って残る")
    func keepsWholeAncestorChain() {
        let rows = [
            folder("/a", depth: 0), folder("/a/b", depth: 1), file("/a/b/note.md", depth: 2),
        ]
        let filtered = [rows[2]]

        let result = SidebarTreeFilter.keepingAncestors(of: filtered, in: rows)

        #expect(result.map(\.url.lastPathComponent) == ["a", "b", "note.md"])
    }

    @Test("一致しない枝は祖先ごと消えたまま")
    func doesNotResurrectUnrelatedBranches() {
        let rows = [
            folder("/a", depth: 0), file("/a/note.md", depth: 1),
            folder("/z", depth: 0), file("/z/other.md", depth: 1),
        ]
        let filtered = [rows[1]]

        let result = SidebarTreeFilter.keepingAncestors(of: filtered, in: rows)

        #expect(result.map(\.url.lastPathComponent) == ["a", "note.md"])
    }

    /// 祖先を pathKey の前置一致で求めると、同じ名前のフォルダが別の階層にあるときに
    /// 取り違える。祖先は「配列上の depth の連なり」で決めること。
    @Test("同名のフォルダが別の階層にあっても、実際に並んでいる親だけが残る")
    func resolvesAncestorsByDepthChainNotPathPrefix() {
        // /x/a と /y/a。残るのは /y/a/note.md なので、祖先は /y と /y/a だけ。
        let rows = [
            folder("/x", depth: 0), folder("/x/a", depth: 1), file("/x/a/other.md", depth: 2),
            folder("/y", depth: 0), folder("/y/a", depth: 1), file("/y/a/note.md", depth: 2),
        ]
        let filtered = [rows[5]]

        let result = SidebarTreeFilter.keepingAncestors(of: filtered, in: rows)

        #expect(result.map(\.url.path) == ["/y", "/y/a", "/y/a/note.md"])
    }

    // MARK: - 素通しの担保

    /// 「素通しになるはず」ではなくコード上の分岐で担保する。ここは body 評価・
    /// キー操作のたびに走る経路にある。
    @Test("絞り込みが効いていなければ入力をそのまま返す")
    func passesThroughWhenNothingFiltered() {
        let rows = [folder("/a", depth: 0), file("/a/note.md", depth: 1)]

        #expect(SidebarTreeFilter.keepingAncestors(of: rows, in: rows).count == rows.count)
    }

    @Test("全行 depth 0(ドリルダウン)なら入力をそのまま返す")
    func passesThroughForFlatRows() {
        let rows = [file("/a.md", depth: 0), file("/b.md", depth: 0)]
        let filtered = [rows[0]]

        let result = SidebarTreeFilter.keepingAncestors(of: filtered, in: rows)

        #expect(result.map(\.url.lastPathComponent) == ["a.md"])
    }
}
