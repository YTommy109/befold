@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// SidebarRowBuilder の行組み立て規則。ドリルダウンが「展開集合が空」の縮退形として
/// 同じ関数を通ることと、depth の割り当て・重複展開の抑止を押さえる。
struct SidebarRowBuilderTests {
    private func folder(_ path: String) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .folder)
    }

    private func folderEntry(at url: URL) -> FileListEntry {
        FileListEntry(url: url, kind: .folder)
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

    /// 列挙に失敗したフォルダは、行を増やさないまま `.expandedFailed` になる。
    /// `failed` を渡し損ねると `.collapsed` に落ち、失敗が「畳んでいる」ように見えるうえ、
    /// → キーが展開を出しても再展開が弾かれて無反応になる(TASK-404)。
    @Test("列挙に失敗したフォルダは行を増やさず、畳んだ状態にも落ちない")
    func failedFolderShowsFailureWithoutAddingRows() {
        let target = folder("/root/dir/a")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [target], expanded: [], childrenByPathKey: [:],
            failed: [target.pathKey], showsDisclosure: true
        )

        #expect(rows.map(\.url) == [target.url])
        #expect(rows.first?.disclosure == .expandedFailed)
    }

    /// 失敗していないフォルダの見た目は変わらない(失敗の判定が全行へ漏れない)。
    @Test("失敗していないフォルダは、失敗集合があっても畳んだ状態のまま")
    func unrelatedFolderIsUnaffectedByFailureSet() {
        let target = folder("/root/dir/a")
        let other = folder("/root/dir/b")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [target, other], expanded: [], childrenByPathKey: [:],
            failed: [target.pathKey], showsDisclosure: true
        )

        #expect(rows.last?.disclosure == .collapsed)
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

    /// 同一フォルダー内にシンボリックリンクと実体が並ぶと、2 行が同じ pathKey を持つ
    /// (TASK-450)。開閉状態は pathKey 単位でしか持てないため、両方の行を「展開済み」に
    /// すると子が並ぶのは先の 1 行だけで、後の行は「三角は開いているのに子が出ない」
    /// 状態になっていた(TASK-454)。先の 1 行だけを持ち主にし、後の行は三角を出さない。
    @Test("同じ pathKey の行が 2 つあっても、開いた三角が出るのは先の 1 行だけ")
    func duplicatePathKeyRowsDoNotBothLookExpanded() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let real = tmp.url.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tmp.url.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let linkEntry = folderEntry(at: link)
        let realEntry = folderEntry(at: real)
        let child = file(real.appendingPathComponent("a.md").path)
        // この前提が崩れる(キーが分かれる)なら、そもそもこの不整合は起きない。
        #expect(linkEntry.pathKey == realEntry.pathKey)

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [linkEntry, realEntry],
            expanded: [realEntry.pathKey],
            childrenByPathKey: [realEntry.pathKey: [child]],
            showsDisclosure: true
        )

        // 子が並ぶのは持ち主(先に現れた link 行)の下だけ。
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows[0].disclosure == .expanded)
        #expect(rows[1].url.lastPathComponent == "a.md")
        // 重複行は三角を出さない(押しても開けない三角を見せない)。
        #expect(rows[2].disclosure == nil)
        #expect(openRowsWithoutChildren(in: rows).isEmpty)
    }

    /// 子リストの到着を待っている間も同じ。両方の行がスピナーを回すと、届いた瞬間に
    /// 片方だけが子を並べて先ほどの不整合に戻る。
    @Test("子が未到着でも、読み込み中の三角が出るのは先の 1 行だけ")
    func duplicatePathKeyRowsDoNotBothShowLoading() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let real = tmp.url.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tmp.url.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let linkEntry = folderEntry(at: link)
        let realEntry = folderEntry(at: real)

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [linkEntry, realEntry],
            expanded: [], childrenByPathKey: [:],
            loading: [realEntry.pathKey], showsDisclosure: true
        )

        #expect(rows.map(\.disclosure) == [.loadingChildren, nil])
    }

    /// 「開いている三角」なのに直後により深い行が続かない行。ここが空でないことが
    /// TASK-454 の症状そのもの。
    private func openRowsWithoutChildren(in rows: [FileListEntry]) -> [FileListEntry] {
        rows.indices.filter { index in
            guard rows[index].disclosure == .expanded else { return false }
            let next = rows.index(after: index)
            return next >= rows.count || rows[next].depth <= rows[index].depth
        }.map { rows[$0] }
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
