import AppKit
import BefoldKit

/// 空タブのサイドバーの材料を、文書タブと同じ共有依存から作る。
extension ViewerWindowManager {
    /// 起点の窓がサイドバーを持たなければ nil(列挙するフォルダが決まらない)。
    func makeBlankTabSidebar(from sourceWindow: NSWindow) -> BlankTabSidebarContext? {
        guard let directory = SidebarInheritance.currentDirectory(of: sourceWindow) else { return nil }
        let seed = SidebarInheritance.seed(from: sourceWindow, opensAsTab: true, replacing: nil, opening: nil)
        return makeBlankTabSidebar(directory: directory, seed: seed)
    }

    /// ディレクトリの一覧を本文に出す窓を開く(ADR 0013 決定 5)。ファイルは開かない。
    /// 表示オプションの当て方は `ViewerDisplayOptionsApplier` が持つ。
    @discardableResult
    func openFolder(_ directory: URL, options: CLIOpenOptions) -> BlankTabWindowController {
        let sidebar = makeBlankTabSidebar(directory: directory, seed: ViewerDisplayOptionsApplier.folderSeed(options))
        ViewerDisplayOptionsApplier.apply(options, toFolderWindow: sidebar.navigator.fileListModel.display)
        NSApplication.shared.activate()
        return blankTabs.openFolder(directory, sidebar: sidebar)
    }

    private func makeBlankTabSidebar(directory: URL, seed: SidebarInheritance.Seed) -> BlankTabSidebarContext {
        BlankTabSidebarContext(
            navigator: SidebarNavigator(
                currentDirectory: directory, entries: [], selection: nil, home: shared.home,
                displayDefaults: shared.displayDefaults,
                git: ViewerWindowAssembler.makeSidebarGitReader(fileIndex: gitFileIndex, statusStore: gitStatusStore)
            ),
            seed: seed,
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
