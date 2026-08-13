@testable import befold
import Foundation
import SwiftUI
import Testing

/// ツリー表示の ← / h が「ルートを変えずにツリー内の親行へ選択を移す」こと(TASK-408)。
///
/// 割り当てそのもの(どのキーがどの動作になるか)は SidebarKeyActionTests が測る。
/// こちらは **親行の決め方**(`FileListSnapshot.parent(of:)`)と、その動作が実際に
/// 選択を動かすところまでの配線を測る。
@Suite
@MainActor
struct SidebarParentRowSelectionTests {
    /// スパイの生存を保つ入れ物(`FileListView.delegate` は弱参照)。
    private let delegates = FileListViewDelegateStore()

    private let root = URL(fileURLWithPath: "/tmp/SidebarParentRowSelectionTests")

    private func entry(_ path: String, kind: FileListEntry.Kind) -> FileListEntry {
        FileListEntry(url: root.appendingPathComponent(path), kind: kind)
    }

    private func makeModel(entries: [FileListEntry], selection: FileListEntry.ID?) -> FileListModel {
        FileListModel(currentDirectory: root, entries: entries, selection: selection)
    }

    /// `[.., src, src/note.md, src/lib, src/lib/deep.md, top.md]` の並び。
    private struct TreeFixture {
        let parent: FileListEntry
        let src: FileListEntry
        let note: FileListEntry
        let lib: FileListEntry
        let deep: FileListEntry
        let top: FileListEntry
        let rows: [FileListEntry]
    }

    private func makeTreeFixture() -> TreeFixture {
        let parent = FileListEntry(url: root.deletingLastPathComponent(), kind: .parentNavigation)
        let src = entry("src", kind: .folder)
        let note = entry("src/note.md", kind: .file)
        let lib = entry("src/lib", kind: .folder)
        let deep = entry("src/lib/deep.md", kind: .file)
        let top = entry("top.md", kind: .file)
        let rows = SidebarRowBuilder.rows(
            parentEntry: parent, rootChildren: [src, top],
            expanded: [src.pathKey, lib.pathKey],
            childrenByPathKey: [src.pathKey: [note, lib], lib.pathKey: [deep]],
            showsDisclosure: true
        )
        return TreeFixture(
            parent: parent, src: src, note: note, lib: lib, deep: deep, top: top, rows: rows
        )
    }

    // MARK: - 親行の決め方

    @Test("親行は、対象より前にある depth がより小さい最後の行")
    func parentRowIsNearestShallowerPrecedingRow() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: nil)

        #expect(model.listSnapshot.parent(of: fixture.note.id)?.id == fixture.src.id)
        #expect(model.listSnapshot.parent(of: fixture.lib.id)?.id == fixture.src.id)
        #expect(model.listSnapshot.parent(of: fixture.deep.id)?.id == fixture.lib.id)
    }

    /// depth 0 の行に親は無い。`..` を親として選んでしまうと、ルート移動の手段が
    /// 選択移動と混ざる(← はルートを変えない、という判断が破れる)。
    @Test("最上位の行(`..` を含む)には親行が無い")
    func topLevelRowsHaveNoParentRow() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: nil)

        #expect(model.listSnapshot.parent(of: fixture.src.id) == nil)
        #expect(model.listSnapshot.parent(of: fixture.top.id) == nil)
        #expect(model.listSnapshot.parent(of: fixture.parent.id) == nil)
    }

    @Test("一覧に無い行を渡したら親行は無い")
    func unknownRowHasNoParentRow() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: nil)

        #expect(model.listSnapshot.parent(of: root.appendingPathComponent("missing.md")) == nil)
    }

    /// 絞り込み中は `SidebarTreeFilter.keepingAncestors` が祖先を足し戻す。親行の判定も
    /// 同じ「配列上の depth の連なり」を源にしているので、答えが割れない。
    @Test("名前フィルタ中でも、足し戻された祖先が親行になる")
    func parentRowFollowsAncestorsKeptByFilter() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: nil)
        model.filterText = "deep*"

        // 先頭は `..`(上位フォルダー行)。フィルタ文字列によらず常に残る。
        #expect(model.visibleEntries.map(\.kind) == [.parentNavigation, .folder, .folder, .file])
        #expect(model.visibleEntries.map(\.depth) == [0, 0, 1, 2])
        #expect(model.listSnapshot.parent(of: fixture.deep.id)?.id == fixture.lib.id)
    }

    // MARK: - キー操作からの配線

    private func makeView(model: FileListModel, onNavigate: @escaping (URL) -> Void) -> FileListView {
        FileListView(
            model: model,
            delegate: delegates.makeSpy(onNavigate: onNavigate),
            onSortOrderChanged: { _ in }
        )
    }

    @Test("ツリー: ファイル行で ← を押すと、ルートは変わらず親フォルダの行へ選択が移る")
    func leftArrowSelectsParentRowWithoutChangingRoot() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: fixture.deep.id)
        model.layoutMode = .tree
        var navigated: [URL] = []
        let view = makeView(model: model) { navigated.append($0) }

        #expect(view.handleKey(.leftArrow) == .handled)

        #expect(model.selection == fixture.lib.id)
        #expect(navigated.isEmpty)
    }

    @Test("ツリー: 畳んだフォルダ行で h を押すと親フォルダの行へ選択が移る")
    func collapsedFolderMovesSelectionToParentRow() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: fixture.lib.id)
        model.layoutMode = .tree
        // 畳んだ状態の lib を選んでいる、という形にする(展開済みなら ← は畳む)。
        model.entries = fixture.rows.filter { $0.id != fixture.deep.id }
            .map { $0.id == fixture.lib.id ? $0.disclosing(.collapsed) : $0 }
        var navigated: [URL] = []
        let view = makeView(model: model) { navigated.append($0) }

        #expect(view.handleKey("h") == .handled)

        #expect(model.selection == fixture.src.id)
        #expect(navigated.isEmpty)
    }

    @Test("ツリー: 最上位の行で ← を押しても何も起きない")
    func topLevelRowIgnoresLeftArrow() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: fixture.top.id)
        model.layoutMode = .tree
        var navigated: [URL] = []
        let view = makeView(model: model) { navigated.append($0) }

        #expect(view.handleKey(.leftArrow) == .ignored)

        #expect(model.selection == fixture.top.id)
        #expect(navigated.isEmpty)
    }

    /// ← がルートを変えなくなったぶん、ルートを上げる手段は cmd+↑ と delete に残る。
    @Test("ツリー: cmd+↑ と delete はルートを親へ移す")
    func commandUpAndDeleteStillNavigateToParent() {
        let fixture = makeTreeFixture()
        for key in [KeyEquivalent.upArrow, .delete] {
            let model = makeModel(entries: fixture.rows, selection: fixture.deep.id)
            model.layoutMode = .tree
            var navigated: [URL] = []
            let view = makeView(model: model) { navigated.append($0) }
            let modifiers: EventModifiers = key == .upArrow ? .command : []

            #expect(view.handleKey(key, modifiers: modifiers) == .handled)

            #expect(navigated == [fixture.parent.url])
        }
    }

    /// ドリルダウンでは ← が従来どおりルートを上げる(モード間で取り違えない)。
    @Test("ドリルダウン: ← は従来どおりルートを親へ移す")
    func drillDownLeftArrowStillNavigatesToParent() {
        let fixture = makeTreeFixture()
        let model = makeModel(entries: fixture.rows, selection: fixture.deep.id)
        model.layoutMode = .drillDown
        var navigated: [URL] = []
        let view = makeView(model: model) { navigated.append($0) }

        #expect(view.handleKey(.leftArrow) == .handled)

        #expect(navigated == [fixture.parent.url])
    }
}
