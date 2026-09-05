@testable import befold
import BefoldKit
import Foundation
import Testing

/// サイドバーヘッダーの表示切り替え 5 種が、注入クロージャではなく
/// `FileListViewDelegate` を通って上位へ届くことの担保(TASK-586)。
///
/// GUI 層は自動テスト対象外なので、ボタンそのものは押せない。押した先で走る
/// `SidebarHeaderView.perform(_:)` と、⋯ メニューの対応表 `displayRequest(for:)` を
/// 直接呼ぶことで、「delegate 以外の経路が生えていない」ことを測る。
@MainActor
struct SidebarDisplayRequestRoutingTests {
    private func makeHeader(delegate: FileListViewDelegateSpy) -> SidebarHeaderView {
        SidebarHeaderView(
            model: FileListModel(
                currentDirectory: URL(fileURLWithPath: "/tmp/SidebarDisplayRequestRoutingTests"),
                entries: [],
                selection: nil
            ),
            delegate: delegate
        )
    }

    @Test("表示切り替えの 5 種はすべて delegate へ届く")
    func allDisplayRequestsReachDelegate() {
        let store = FileListViewDelegateStore()
        let spy = store.makeSpy()
        let header = makeHeader(delegate: spy)

        let requests: [SidebarDisplayRequest] = [
            .display(.setSortOrder(.alphabetical)),
            .display(.toggleHiddenFiles),
            .display(.toggleChangedFilesOnly),
            .display(.toggleLayoutMode),
            .slideMode,
        ]
        for request in requests {
            header.perform(request)
        }

        #expect(spy.displayChanges == requests)
    }

    @Test("⋯ メニューの各項目は対応する表示切り替えへ写る")
    func overflowItemsMapToDisplayRequests() {
        #expect(
            SidebarHeaderView.displayRequest(for: .sortFoldersFirst)
                == .display(.setSortOrder(.foldersFirst))
        )
        #expect(
            SidebarHeaderView.displayRequest(for: .sortAlphabetical)
                == .display(.setSortOrder(.alphabetical))
        )
        #expect(SidebarHeaderView.displayRequest(for: .hiddenFiles) == .display(.toggleHiddenFiles))
    }
}
