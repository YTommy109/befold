import AppKit
import BefoldKit

/// 空タブのサイドバーの材料を、文書タブと同じ共有依存から作る。
extension ViewerWindowManager {
    /// サイドバーの「新しいタブ/ウィンドウで開く」の振り分け。フォルダーならその一覧の窓
    /// (`BlankTabCoordinator.openFolder`)、ファイルなら文書の窓を開く。種別はファイルシステムの事実で決める。
    func openElsewhere(
        _ url: URL, disposition: OpenDisposition, placement: NewTabPlacement, relativeTo sourceWindow: NSWindow?
    ) {
        guard fileReader.isDirectory(at: url) else {
            openViewer(for: url, disposition: disposition, relativeTo: sourceWindow, tabPlacement: placement)
            return
        }
        blankTabs.openFolder(url, options: CLIOpenOptions(), disposition: disposition, relativeTo: sourceWindow)
    }

    func makeBlankTabSidebar(directory: URL, seed: SidebarInheritance.Seed) -> BlankTabSidebarContext {
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
            openElsewhere: { [weak self] in self?.openElsewhere($0, disposition: $1, placement: .end, relativeTo: $2) }
        )
    }
}
