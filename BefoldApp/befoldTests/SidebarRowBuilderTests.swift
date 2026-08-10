@testable import befold
import Foundation
import Testing

/// SidebarRowBuilder の行組み立て規則。ドリルダウンが「展開集合が空」の縮退形として
/// 同じ関数を通ることと、depth の割り当て・重複展開の抑止を押さえる。
struct SidebarRowBuilderTests {
    private func folder(_ path: String) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .folder)
    }

    private func file(_ path: String) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .file)
    }

    @Test("展開集合が空なら、親移動行 + ルート直下の行がそのまま並び全て depth 0")
    func emptyExpansionDegeneratesToDrillDown() {
        let parent = FileListEntry(url: URL(fileURLWithPath: "/root"), kind: .parentNavigation)
        let children = [folder("/root/dir/a"), file("/root/dir/b.md")]

        let rows = SidebarRowBuilder.rows(
            parentEntry: parent, rootChildren: children, expanded: [], childrenByPathKey: [:]
        )

        #expect(rows.map(\.url) == [parent.url, children[0].url, children[1].url])
        #expect(rows.allSatisfy { $0.depth == 0 })
    }

    @Test("親移動行が無ければ、ルート直下の行だけが並ぶ")
    func omitsParentNavigationWhenAbsent() {
        let children = [file("/root/dir/a.md")]

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: children, expanded: [], childrenByPathKey: [:]
        )

        #expect(rows.map(\.url) == [children[0].url])
    }

    @Test("展開したフォルダの配下が、その行の直後に depth 1 で並ぶ")
    func expandedFolderInsertsChildrenAfterItsRow() {
        let dir = folder("/root/dir")
        let tail = file("/root/z.md")
        let grandChild = file("/root/dir/x.md")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [dir, tail], expanded: [dir.pathKey],
            childrenByPathKey: [dir.pathKey: [grandChild]]
        )

        #expect(rows.map(\.url) == [dir.url, grandChild.url, tail.url])
        #expect(rows.map(\.depth) == [0, 1, 0])
    }

    @Test("入れ子の展開で depth が 0 / 1 / 2 と積み上がる")
    func nestedExpansionAccumulatesDepth() {
        let outer = folder("/root/a")
        let inner = folder("/root/a/b")
        let leaf = file("/root/a/b/c.md")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [outer], expanded: [outer.pathKey, inner.pathKey],
            childrenByPathKey: [outer.pathKey: [inner], inner.pathKey: [leaf]]
        )

        #expect(rows.map(\.url) == [outer.url, inner.url, leaf.url])
        #expect(rows.map(\.depth) == [0, 1, 2])
    }

    @Test("行に現れないフォルダのキーが展開集合にあっても無視される")
    func ignoresExpansionKeysNotPresentInRows() {
        let dir = folder("/root/dir")
        let absent = folder("/root/absent")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [dir], expanded: [absent.pathKey],
            childrenByPathKey: [absent.pathKey: [file("/root/absent/x.md")]]
        )

        #expect(rows.map(\.url) == [dir.url])
    }

    @Test("展開されていても材料が無いフォルダは、子を持たない行として扱う")
    func treatsMissingChildrenAsEmpty() {
        let dir = folder("/root/dir")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [dir], expanded: [dir.pathKey], childrenByPathKey: [:]
        )

        #expect(rows.map(\.url) == [dir.url])
    }

    @Test("循環する材料を与えても行が重複せず再帰が止まる")
    func stopsRecursionOnCycle() {
        // シンボリックリンク越しに a/ → b/ → a/ と辿れる形を材料で直接与える。
        let dirA = folder("/root/a")
        let dirB = folder("/root/a/b")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [dirA], expanded: [dirA.pathKey, dirB.pathKey],
            childrenByPathKey: [dirA.pathKey: [dirB], dirB.pathKey: [dirA]]
        )

        #expect(rows.map(\.url) == [dirA.url, dirB.url, dirA.url])
        #expect(rows.map(\.depth) == [0, 1, 2])
    }

    /// depth / disclosure は行の見た目(インデント量・開閉三角・ドリルダウンの ">")を
    /// 決めるため、等値から外すと SwiftUI が行を描き直さず、表示モードの切り替えが
    /// 同じディレクトリのままだと画面に出ない。identity 比較が要るのは
    /// `FolderListingSource` だけで、そちらは自前の `==` を持つ。
    @Test("depth と disclosure は等値・ハッシュに参加する")
    func depthAndDisclosureParticipateInEquality() {
        let entry = file("/root/a.md")
        let indented = entry.indented(to: 3)
        let disclosed = entry.disclosing(.collapsed)

        #expect(entry != indented)
        #expect(entry != disclosed)
        #expect(Set([entry, indented, disclosed]).count == 3)
        #expect(indented.depth == 3)
    }
}
