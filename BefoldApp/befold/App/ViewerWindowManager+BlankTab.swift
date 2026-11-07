import AppKit
import BefoldKit

/// 空タブのサイドバーの材料を、文書タブと同じ共有依存から作る。
extension ViewerWindowManager {
    /// 起点の窓がサイドバーを持たなければ nil(列挙するフォルダが決まらない)。
    func makeBlankTabSidebar(from sourceWindow: NSWindow) -> BlankTabSidebarContext? {
        guard let directory = SidebarInheritance.currentDirectory(of: sourceWindow) else { return nil }
        return BlankTabSidebarContext(
            navigator: SidebarNavigator(
                currentDirectory: directory, entries: [], selection: nil, home: shared.home,
                displayDefaults: shared.displayDefaults,
                git: ViewerWindowAssembler.makeSidebarGitReader(fileIndex: gitFileIndex, statusStore: gitStatusStore)
            ),
            seed: SidebarInheritance.seed(from: sourceWindow, opensAsTab: true, replacing: nil, opening: nil),
            sidebarState: shared.sidebarState,
            replaceWithDocument: { [weak self] url, window in
                self?.openViewer(for: url, disposition: .currentTab, relativeTo: window)
            },
            openElsewhere: { [weak self] url, disposition, window in
                self?.openViewer(for: url, disposition: disposition, relativeTo: window)
            }
        )
    }
}
