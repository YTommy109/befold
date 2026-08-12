@testable import befold
import BefoldKit
import Foundation
import SwiftUI
import Testing

/// 絞り込みで選択行が隠れている状態のキーボード操作(TASK-418)。
///
/// `filterText` は `presentedPathKey` の例外を持たない(git 絞り込みだけが持つ)ため、
/// 開いているファイルに一致しないパターンを打つと選択行が一覧から落ちる。この状態から
/// キーボードだけで絞り込み結果へ到達できることを見る。
@Suite
@MainActor
struct FileListViewFilteredKeyboardTests {
    private let directory = URL(fileURLWithPath: "/tmp/FileListViewFilteredKeyboardTests")

    private func makeEntry(_ name: String) -> FileListEntry {
        FileListEntry(url: directory.appendingPathComponent(name), kind: .file)
    }

    /// `alpha.md` を選択した状態で、それに一致しない `beta` で絞り込んだビュー。
    private func makeFilteredView() -> (view: FileListView, hits: [FileListEntry]) {
        let alpha = makeEntry("alpha.md")
        let beta1 = makeEntry("beta1.md")
        let beta2 = makeEntry("beta2.md")
        let model = FileListModel(
            currentDirectory: directory, entries: [alpha, beta1, beta2], selection: alpha.id
        )
        model.filterText = "beta*"
        let view = FileListView(
            model: model,
            onSelect: { _ in },
            onNavigate: { _ in },
            onSortOrderChanged: { _ in },
            onOpenElsewhere: { _, _ in }
        )
        return (view, [beta1, beta2])
    }

    @Test("選択行が絞り込みで隠れていても ↓ で絞り込み結果の先頭へ移る")
    func downArrowMovesToFirstMatchWhenSelectionIsHidden() {
        let (view, hits) = makeFilteredView()
        #expect(view.model.listSnapshot.entry(for: view.model.selection) == nil)

        let result = view.handleKey(.downArrow)

        #expect(result == .handled)
        #expect(view.model.selection == hits[0].id)
    }

    @Test("選択行が絞り込みで隠れていても ↑ で絞り込み結果の末尾へ移る")
    func upArrowMovesToLastMatchWhenSelectionIsHidden() {
        let (view, hits) = makeFilteredView()

        let result = view.handleKey(.upArrow)

        #expect(result == .handled)
        #expect(view.model.selection == hits[1].id)
    }

    @Test("j / k も隠れた選択から絞り込み結果へ入れる")
    func vimKeysAlsoRecoverFromHiddenSelection() {
        let (downView, hits) = makeFilteredView()
        #expect(downView.handleKey("j") == .handled)
        #expect(downView.model.selection == hits[0].id)

        let (upView, _) = makeFilteredView()
        #expect(upView.handleKey("k") == .handled)
        #expect(upView.model.selection == hits[1].id)
    }

    /// AC#2。絞り込み中に移した選択は、絞り込みを解除しても同じ行を指したままで、
    /// そこから続けて矢印キーで動ける(全件一覧での位置へ素直に戻る)。
    @Test("絞り込みを解除しても選択位置が破綻しない")
    func clearingFilterKeepsSelectionUsable() {
        let (view, hits) = makeFilteredView()
        _ = view.handleKey(.downArrow)

        view.model.filterText = ""

        #expect(view.model.selection == hits[0].id)
        #expect(view.handleKey(.downArrow) == .handled)
        #expect(view.model.selection == hits[1].id)
    }

    /// AC#3。キーハンドラの同期区間で絞り込みが 1 回しか走らないこと。
    ///
    /// 選択の書き込みが起こす画面スクロール追従(`scrollSelectionIntoView`)は
    /// 次のランループで別途一覧を読み直すため、ここでは数えない(そちらは
    /// 一覧差し替えと選択書き込みの順序が逆転する経路があり、読み直しが正しい)。
    @Test("1 回のキー操作で絞り込みの評価は 1 回だけ")
    func keyPressEvaluatesSnapshotOnce() {
        let (view, _) = makeFilteredView()
        view.model.resetSnapshotEvaluationCount()

        _ = view.handleKey(.downArrow)

        #expect(view.model.snapshotEvaluationCount == 1)
    }

    /// ← (ツリー内で親行へ移る)も同じ不変条件に従うこと(TASK-443)。
    ///
    /// 以前は `FileListModel.parentRow(of:)` を呼んでおり、その中で `visibleEntries` を
    /// 読み直すためこの経路だけ 2 回評価していた。判定を `FileListSnapshot.parent(of:)` へ
    /// 移して、キーハンドラが先頭で採った 1 つを使い回す形に閉じてある。
    @Test("ツリー表示の ← でも絞り込みの評価は 1 回だけ")
    func selectParentKeyEvaluatesSnapshotOnce() {
        let parent = FileListEntry(url: directory, kind: .folder)
        let child = FileListEntry(url: directory.appendingPathComponent("child.md"), kind: .file)
        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [parent],
            expanded: [parent.pathKey],
            childrenByPathKey: [parent.pathKey: [child]],
            showsDisclosure: true
        )
        let model = FileListModel(
            currentDirectory: directory, entries: rows, selection: child.id
        )
        model.layoutMode = .tree
        let view = FileListView(
            model: model,
            onSelect: { _ in },
            onNavigate: { _ in },
            onSortOrderChanged: { _ in },
            onOpenElsewhere: { _, _ in }
        )
        model.resetSnapshotEvaluationCount()

        #expect(view.handleKey(.leftArrow) == .handled)

        #expect(model.selection == parent.id)
        #expect(model.snapshotEvaluationCount == 1)
    }

    @Test("絞り込み結果が空なら隠れた選択からの移動は何も起こさない")
    func hiddenSelectionWithNoMatchesIsIgnored() {
        let (view, _) = makeFilteredView()
        view.model.filterText = "no-such-name*"
        let before = view.model.selection

        #expect(view.handleKey(.downArrow) == .ignored)
        #expect(view.handleKey(.upArrow) == .ignored)
        #expect(view.model.selection == before)
    }
}
