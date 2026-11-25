import AppKit
import BefoldKit

/// 空タブのサイドバーの材料を、文書タブと同じ共有依存から作る。
extension ViewerWindowManager {
    /// 起点の窓がサイドバーを持たなければ nil(列挙するフォルダが決まらない)。
    func makeBlankTabSidebar(from sourceWindow: NSWindow) -> BlankTabSidebarContext? {
        guard let directory = SidebarInheritance.currentDirectory(of: sourceWindow) else { return nil }
        return makeBlankTabSidebar(
            directory: directory,
            seed: SidebarInheritance.seed(from: sourceWindow, opensAsTab: true, replacing: nil, opening: nil)
        )
    }

    /// ディレクトリの一覧を本文に出す窓を開く(ADR 0013 決定 5)。ファイルは開かない。
    ///
    /// CLI の表示オプションのうち、文書の無い窓に意味があるのはサイドバーの 3 つ(並び順・
    /// 不可視ファイル・開閉)だけで、文書タブと同じく**この窓限りの上書き**として当てる
    /// (保存された既定値は書き換えない)。開閉はディレクトリを開いたので既定で表示する
    /// (`--no-sidebar` が優先。文書タブの `forceSidebarVisible` と同じ解決順)。
    @discardableResult
    func openFolder(_ directory: URL, options: CLIOpenOptions) -> BlankTabWindowController {
        var seed = SidebarInheritance.Seed.none
        seed.sidebarCollapsed = options.showSidebar.map { !$0 } ?? false
        let sidebar = makeBlankTabSidebar(directory: directory, seed: seed)
        sidebar.navigator.fileListModel.display.applyCLIOverride(
            sortOrder: options.sortOrder != nil ? options.viewerSortOrder : nil,
            showHiddenFiles: options.showHiddenFiles
        )
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
