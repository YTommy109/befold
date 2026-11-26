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

    /// 本文に何を出すか(ADR 0013)。`.file` は空タブの画面、`.folder(D)` は D の一覧。
    /// 書くのはこの窓の入口(フォルダー行の選択・フォルダーへの移動・`befold <ディレクトリ>`)だけ。
    let presentationIntent = PresentationIntent()

    /// - Parameter folder: 本文に一覧を出すフォルダー(`befold <ディレクトリ>` など、ディレクトリを
    ///   開く入口)。nil なら空タブの画面から始める。一覧はサイドバーの部品を使うので、
    ///   サイドバーが無ければ渡しても空タブの画面のまま。
    init(
        sidebar sidebarContext: BlankTabSidebarContext? = nil, presenting folder: URL? = nil,
        onClose: @escaping (BlankTabWindowController) -> Void
    ) {
        self.onClose = onClose
        self.sidebarContext = sidebarContext
        let window = ViewerWindowChrome.makeWindow(fileURL: nil)
        super.init(window: window)
        presentationIntent.onChange = { [weak self] in self?.applyTitle() }
        if let folder, sidebarContext != nil { presentationIntent.present(.folder(folder)) }
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
        let content = BlankTabContentView(
            intent: presentationIntent, fileListModel: navigator.fileListModel,
            onSelectFile: { [weak self] in self?.fileListDidSelectFile($0) },
            onNavigateToFolder: { [weak self] in self?.fileListDidRequestNavigation(to: $0) }
        )
        let splitViewController = ViewerWindowAssembler.makeSidebarSplit(
            sidebar: FileListView(model: navigator.fileListModel, delegate: self), content: content,
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

    /// タイトルは一覧を出しているフォルダー、出していなければ「新しいタブ」。
    private func applyTitle() {
        guard let window else { return }
        guard let folder = presentationIntent.target.folderURL else {
            window.title = String(localized: "menu.file.newTab", bundle: .l10n)
            window.representedURL = nil
            return
        }
        ViewerWindowChrome.applyURL(folder, presenting: .folder(folder), to: window)
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
        presentationIntent.presentFileIfFolderVanished() // 文書が無いので空タブの画面へ戻る
        sidebarContext?.navigator.refreshFileList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

/// 空タブの本文。意図がフォルダーならその一覧(文書タブの本文と同じ `FolderListingView`)、
/// でなければ空タブの画面を出す。文書が無いので、開いているファイルの補いと再読込の世代は渡さない。
private struct BlankTabContentView: View {
    let intent: PresentationIntent
    let fileListModel: FileListModel
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void

    var body: some View {
        if let folder = intent.target.folderURL {
            FolderListingView(
                directory: folder,
                sortOrder: fileListModel.display.sortOrder,
                showHiddenFiles: fileListModel.display.showHiddenFiles,
                filter: fileListModel.listFilter,
                source: fileListModel.listingSource(for: folder),
                onSelectFile: onSelectFile,
                onNavigateToFolder: onNavigateToFolder
            )
        } else {
            BlankTabView()
        }
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
