@testable import befold
import Foundation
import Testing

/// 開閉三角の 4 状態(未到着 / 空フォルダ / 絞り込みで 0 / 列挙失敗)の区別
/// (TASK-361.4 の AC #10、列挙失敗は TASK-404)。
/// GUI 層は自動テスト対象外なので、区別できていることはこの純粋関数のテストが唯一の測り方。
@Suite
struct SidebarDisclosureTests {
    @Test("展開していなければ畳んだ状態")
    func collapsedWhenNotExpanded() {
        #expect(
            SidebarDisclosure.state(
                isExpanded: false, didFail: false, loadedChildCount: 3, visibleChildCount: 3
            ) == .collapsed
        )
    }

    /// 子の件数が nil(未到着)と 0(空フォルダ)を混ぜると、読み込み中が
    /// 「空のフォルダ」として確定表示される。
    @Test("子が未到着なら読み込み中で、空フォルダとは別の状態")
    func loadingIsDistinctFromEmpty() {
        let loading = SidebarDisclosure.state(
            isExpanded: true, didFail: false, loadedChildCount: nil, visibleChildCount: 0
        )
        let empty = SidebarDisclosure.state(
            isExpanded: true, didFail: false, loadedChildCount: 0, visibleChildCount: 0
        )

        #expect(loading == .loadingChildren)
        #expect(empty == .expandedEmpty(isFiltered: false))
        #expect(loading != empty)
    }

    /// 届いている子はあるのに 1 行も出ていない = 絞り込みで消えた。
    /// 「本当に空」と言い切ると、絞り込みを解除すれば見えるものを取り違える。
    @Test("届いた子があるのに可視 0 なら、絞り込みで消えたと区別できる")
    func filteredEmptyIsDistinctFromTrulyEmpty() {
        let filtered = SidebarDisclosure.state(
            isExpanded: true, didFail: false, loadedChildCount: 5, visibleChildCount: 0
        )

        #expect(filtered == .expandedEmpty(isFiltered: true))
        #expect(filtered != .expandedEmpty(isFiltered: false))
    }

    /// 列挙に失敗したフォルダには届く子リストが無く、`loadedChildCount` は永久に nil。
    /// 失敗を後から判定すると読み込み中のまま回り続け、空として扱うと
    /// 「中身が無い」と言い切ってしまう。どちらとも別の状態になることを固定する。
    @Test("列挙失敗は、読み込み中とも空フォルダとも別の状態")
    func failureIsDistinctFromLoadingAndEmpty() {
        let failed = SidebarDisclosure.state(
            isExpanded: true, didFail: true, loadedChildCount: nil, visibleChildCount: 0
        )

        #expect(failed == .expandedFailed)
        #expect(failed != .loadingChildren)
        #expect(failed != .expandedEmpty(isFiltered: false))
        #expect(failed != .expandedEmpty(isFiltered: true))
    }

    /// 失敗したフォルダを畳んだら、失敗の表示も消える(畳んだ行は畳んだ見た目)。
    @Test("畳んでいれば、失敗していても畳んだ状態")
    func collapsedWinsOverFailure() {
        #expect(
            SidebarDisclosure.state(
                isExpanded: false, didFail: true, loadedChildCount: nil, visibleChildCount: 0
            ) == .collapsed
        )
    }

    @Test("子が見えていれば展開状態")
    func expandedWhenChildrenVisible() {
        #expect(
            SidebarDisclosure.state(
                isExpanded: true, didFail: false, loadedChildCount: 5, visibleChildCount: 2
            ) == .expanded
        )
    }
}

/// 絞り込み後の行配列に対する「見えている子が 0」の確定(SidebarDisclosureResolver)。
@Suite
struct SidebarDisclosureResolverTests {
    private func folder(
        _ path: String, depth: Int, _ state: SidebarDisclosureState?
    ) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .folder)
            .indented(to: depth).disclosing(state)
    }

    private func file(_ path: String, depth: Int) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .file).indented(to: depth)
    }

    @Test("子行が残っていれば展開のまま")
    func keepsExpandedWhenChildRemains() {
        let rows = [folder("/a", depth: 0, .expanded), file("/a/1.md", depth: 1)]

        #expect(SidebarDisclosureResolver.resolving(rows).first?.disclosure == .expanded)
    }

    @Test("子行が絞り込みで全部消えていれば、絞り込みによる空へ落とす")
    func marksFilteredEmptyWhenNoChildRemains() {
        let rows = [folder("/a", depth: 0, .expanded), file("/b.md", depth: 0)]

        #expect(
            SidebarDisclosureResolver.resolving(rows).first?.disclosure
                == .expandedEmpty(isFiltered: true)
        )
    }

    /// 孫だけが残って直接の子が消えることは、深さ優先の畳み方では起こらない
    /// (子が消えれば孫も一緒に消える)。それでも depth の比較を誤ると孫を子と数えるため、
    /// 「より深い行はあるが直接の子は無い」形で押さえる。
    @Test("直接の子でない深い行は、子として数えない")
    func doesNotCountGrandchildrenAsChildren() {
        let rows = [folder("/a", depth: 0, .expanded), file("/a/b/1.md", depth: 2)]

        #expect(
            SidebarDisclosureResolver.resolving(rows).first?.disclosure
                == .expandedEmpty(isFiltered: true)
        )
    }

    @Test("組み立て時点で空と分かっている行には触らない")
    func leavesTrulyEmptyUntouched() {
        let rows = [folder("/a", depth: 0, .expandedEmpty(isFiltered: false))]

        #expect(
            SidebarDisclosureResolver.resolving(rows).first?.disclosure
                == .expandedEmpty(isFiltered: false)
        )
    }

    /// ドリルダウン表示では三角そのものが無いので、走査せずそのまま返る。
    @Test("開閉三角を持たない配列は素通しで返る")
    func passesThroughRowsWithoutDisclosure() {
        let rows = [file("/a.md", depth: 0), file("/b.md", depth: 0)]

        #expect(SidebarDisclosureResolver.resolving(rows).allSatisfy { $0.disclosure == nil })
    }
}
