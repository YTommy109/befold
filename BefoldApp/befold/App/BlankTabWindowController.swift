import AppKit
import BefoldKit
import SwiftUI

/// 空タブのサイドバーの材料。起点の窓が無い空タブには列挙するフォルダが無いので、これも無い。
@MainActor
struct BlankTabSidebarContext {
    let navigator: SidebarNavigator
    let seed: SidebarInheritance.Seed
    let sidebarState: SidebarStateStore
    /// このタブを文書へ置き換え、置き換えた文書タブを返す。開けなければ nil。
    let replaceWithDocument: (URL, NSWindow) -> ViewerWindowController?
    let openElsewhere: (URL, OpenDisposition, NSWindow) -> Void
}

/// 空タブの表示と閉じる通知。文書を選ぶまでレンダラと文書のファイル監視は生成しない
/// (`ViewerStore` も描画面も持たない)。サイドバーは文書タブと同じ部品を使う。
final class BlankTabWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: (BlankTabWindowController) -> Void
    private(set) var isClosed = false
    private var toolbarController: ViewerToolbarController?
    let sidebarContext: BlankTabSidebarContext?
    /// 実体は contentViewController が保持するので weak。
    weak var sidebarCollapsible: (any SidebarCollapsible)?
    /// サイドバーの git 状態の比較基準。新しいタブと同じく既定値から始める。
    var comparisonTarget = GitComparisonTarget.windowDefault

    init(sidebar sidebarContext: BlankTabSidebarContext? = nil, onClose: @escaping (BlankTabWindowController) -> Void) {
        self.onClose = onClose
        self.sidebarContext = sidebarContext
        let window = ViewerWindowChrome.makeWindow(fileURL: nil)
        super.init(window: window)
        toolbarController = ViewerToolbarController(window: window, host: nil, hasSidebar: sidebarContext != nil)
        window.contentViewController = makeContent()
        DocumentFileDropView.install(on: window)
        ViewerWindowChrome.applyInitialFrame(nil, to: window, kind: .viewer, isOccupied: { _ in false })
        window.delegate = self
        if let sidebarContext {
            sidebarContext.navigator.attach(
                to: self, adopting: sidebarContext.seed.listing, expanding: sidebarContext.seed.expansion
            )
            sidebarContext.navigator.refreshFileList()
        }
    }

    private func makeContent() -> NSViewController {
        guard let sidebarContext else { return NSHostingController(rootView: BlankTabView()) }
        let navigator = sidebarContext.navigator
        let sidebarState = sidebarContext.sidebarState
        let splitViewController = ViewerWindowAssembler.makeSidebarSplit(
            sidebar: FileListView(model: navigator.fileListModel, delegate: self), content: BlankTabView(),
            initialCollapsed: ViewerWindowOpenPolicy.initialSidebarCollapsed(
                kind: .viewer, showSidebar: nil, forceSidebarVisible: false,
                sourceCollapsed: sidebarContext.seed.sidebarCollapsed,
                remembered: sidebarState.lastToggledCollapsed
            ),
            allowsSidebar: ViewerWindowKind.viewer.allowsSidebar, sidebarState: sidebarState
        )
        sidebarCollapsible = splitViewController
        return splitViewController
    }

    /// 文書へ置き換わって閉じる。
    func close(replacedBy window: NSWindow?) {
        (self.window as? ViewerDocumentWindow)?.replacement = window
        close()
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        sidebarContext?.navigator.cancelPendingListing()
        onClose(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window else { return }
        ViewerTabGrouping.syncWindowsMenuMembership(among: ViewerTabGrouping.tabWindows(of: window))
        sidebarContext?.navigator.refreshFileList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

private struct BlankTabView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "tab.empty.title", bundle: .l10n))
                .font(.title2)
            Text(String(localized: "tab.empty.detail", bundle: .l10n))
                .foregroundStyle(.secondary)
            Button(String(localized: "menu.file.open", bundle: .l10n)) {
                NSApp.sendAction(#selector(AppDelegate.showOpenPanel), to: nil, from: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
