@testable import befold
import BefoldKit
import Foundation
import Testing

/// サイドバーヘッダーの表示切り替え 4 種が、注入クロージャではなく
/// `FileListViewDelegate` を通って上位へ届くことの担保(TASK-586 / TASK-590)。
///
/// GUI 層は自動テスト対象外なので、ボタンそのものは押せない。ボタンが発行する Kind を
/// 受ける `SidebarHeaderView.selectControl(_:)` と、⋯ メニューの `selectOverflowItem(_:)` を
/// 直接呼び、**Kind → `SidebarDisplayChange` の対応表ごと** delegate に届く値で固定する。
/// 対応を入れ替えると落ちる。テストが通らないのは SwiftUI `Button` の中の
/// `onSelectControl(control.kind)` 1 行だけで、そこに判断は無い。
@MainActor
struct SidebarDisplayChangeRoutingTests {
    private func makeModel() -> FileListModel {
        FileListModel(
            currentDirectory: URL(fileURLWithPath: "/tmp/SidebarDisplayChangeRoutingTests"),
            entries: [],
            selection: nil
        )
    }

    private func makeHeader(
        model: FileListModel? = nil, delegate: FileListViewDelegateSpy
    ) -> SidebarHeaderView {
        SidebarHeaderView(model: model ?? makeModel(), delegate: delegate)
    }

    @Test("ヘッダーのボタン Kind は対応する表示切り替えとして delegate へ届く", arguments: [
        (SidebarHeaderControl.Kind.layoutMode, SidebarDisplayChange.toggleLayoutMode),
        (SidebarHeaderControl.Kind.changedFilesOnly, SidebarDisplayChange.toggleChangedFilesOnly),
    ])
    func headerControlsReachDelegate(kind: SidebarHeaderControl.Kind, expected: SidebarDisplayChange) {
        let store = FileListViewDelegateStore()
        let spy = store.makeSpy()
        let header = makeHeader(delegate: spy)

        header.selectControl(kind)

        #expect(spy.displayChanges == [expected])
    }

    @Test("⋯ メニューの各項目は対応する表示切り替えとして delegate へ届く", arguments: [
        (SidebarOverflowItem.Kind.sortFoldersFirst, SidebarDisplayChange.setSortOrder(.foldersFirst)),
        (SidebarOverflowItem.Kind.sortAlphabetical, SidebarDisplayChange.setSortOrder(.alphabetical)),
        (SidebarOverflowItem.Kind.hiddenFiles, SidebarDisplayChange.toggleHiddenFiles),
    ])
    func overflowItemsReachDelegate(kind: SidebarOverflowItem.Kind, expected: SidebarDisplayChange) {
        let store = FileListViewDelegateStore()
        let spy = store.makeSpy()
        let header = makeHeader(delegate: spy)

        header.selectOverflowItem(kind)

        #expect(spy.displayChanges == [expected])
    }

    /// 名前フィルターは窓の一時状態で、表示 4 値ではない。delegate へ上げず、
    /// ヘッダー内で開閉だけが動く。
    @Test("フィルターのボタンは delegate へ届かず、フィルター欄の開閉だけを動かす")
    func filterControlTogglesLocallyWithoutDelegate() {
        let store = FileListViewDelegateStore()
        let spy = store.makeSpy()
        let model = makeModel()
        let header = makeHeader(model: model, delegate: spy)

        header.selectControl(.filter)
        #expect(model.transient.isFilterActive)
        header.selectControl(.filter)
        #expect(!model.transient.isFilterActive)

        #expect(spy.displayChanges.isEmpty)
    }

    /// ⋯ は Menu が自前で開く。Kind が発行されても delegate へは何も届かない。
    @Test("⋯ のボタン Kind は何も起こさない")
    func overflowControlIsInert() {
        let store = FileListViewDelegateStore()
        let spy = store.makeSpy()
        let header = makeHeader(delegate: spy)

        header.selectControl(.overflow)

        #expect(spy.displayChanges.isEmpty)
    }
}
