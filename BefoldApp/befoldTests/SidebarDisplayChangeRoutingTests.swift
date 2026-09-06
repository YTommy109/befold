@testable import befold
import BefoldKit
import Foundation
import Testing

/// サイドバーヘッダーの表示切り替え 4 種が、注入クロージャではなく
/// `FileListViewDelegate` を通って上位へ届くことの担保(TASK-586)。
///
/// GUI 層は自動テスト対象外なので、ボタンそのものは押せない。押した先で走る
/// `SidebarHeaderView.perform(_:)` と、⋯ メニューの対応表 `displayChange(for:)` を
/// 直接呼ぶことで、「delegate 以外の経路が生えていない」ことを測る。
@MainActor
struct SidebarDisplayChangeRoutingTests {
    private func makeHeader(delegate: FileListViewDelegateSpy) -> SidebarHeaderView {
        SidebarHeaderView(
            model: FileListModel(
                currentDirectory: URL(fileURLWithPath: "/tmp/SidebarDisplayChangeRoutingTests"),
                entries: [],
                selection: nil
            ),
            delegate: delegate
        )
    }

    @Test("表示切り替えの 4 種はすべて delegate へ届く")
    func allDisplayChangesReachDelegate() {
        let store = FileListViewDelegateStore()
        let spy = store.makeSpy()
        let header = makeHeader(delegate: spy)

        let changes: [SidebarDisplayChange] = [
            .setSortOrder(.alphabetical),
            .toggleHiddenFiles,
            .toggleChangedFilesOnly,
            .toggleLayoutMode,
        ]
        for change in changes {
            header.perform(change)
        }

        #expect(spy.displayChanges == changes)
    }

    @Test("⋯ メニューの各項目は対応する表示切り替えへ写る")
    func overflowItemsMapToDisplayChanges() {
        #expect(
            SidebarHeaderView.displayChange(for: .sortFoldersFirst) == .setSortOrder(.foldersFirst)
        )
        #expect(
            SidebarHeaderView.displayChange(for: .sortAlphabetical) == .setSortOrder(.alphabetical)
        )
        #expect(SidebarHeaderView.displayChange(for: .hiddenFiles) == .toggleHiddenFiles)
    }
}
