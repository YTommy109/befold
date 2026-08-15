import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ツリー⇄リスト切り替えでの展開状態とカレントフォルダーの引き継ぎ(TASK-481)。
///
/// - ツリー→リスト: 展開を捨てずに root を記録し、選択ファイルの親フォルダーへ移る
/// - リスト→ツリー: 記録した root の配下に居れば root と展開を復元し、選択までの経路を開く
/// - リスト中のフォルダー移動は展開を温存する(破棄はツリー表示中のルート変更だけ)
@Suite
@MainActor
struct SidebarLayoutTransitionTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// scrollRowToVisible の要求行を記録するスパイ(FileListModelScrollTests と同型)。
    private final class SpyTableView: NSTableView {
        private(set) var scrolledRows: [Int] = []
        override func scrollRowToVisible(_ row: Int) {
            scrolledRows.append(row)
        }
    }

    private struct Fixture {
        let base: URL
        let sub: URL
        let inner: URL
        let deepFile: URL
        let sibling: URL
        let outside: URL
    }

    private func makeFixture(_ name: String) -> Fixture {
        let base = Self.home.appendingPathComponent("SidebarLayoutTransitionTests-\(name)")
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let inner = sub.appendingPathComponent("inner", isDirectory: true)
        return Fixture(
            base: base,
            sub: sub,
            inner: inner,
            deepFile: inner.appendingPathComponent("deep.mmd"),
            sibling: base.appendingPathComponent("a.mmd"),
            outside: Self.home.appendingPathComponent(
                "SidebarLayoutTransitionTests-\(name)-outside", isDirectory: true
            )
        )
    }

    /// ディレクトリごとの固定エントリを返す lister を備えたナビゲーター
    /// (前例: SidebarPostSwitchSyncTests)。実 FS には触れない。
    private func makeNavigator(
        _ fixture: Fixture, currentDirectory: URL, selection: URL?, currentFile: URL
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let listings: [String: [FileListEntry]] = [
            fixture.base.normalizedPathKey: [
                FileListEntry(url: fixture.sub, kind: .folder),
                FileListEntry(url: fixture.sibling, kind: .file),
            ],
            fixture.sub.normalizedPathKey: [FileListEntry(url: fixture.inner, kind: .folder)],
            fixture.inner.normalizedPathKey: [FileListEntry(url: fixture.deepFile, kind: .file)],
            fixture.outside.normalizedPathKey: [],
        ]
        let listing = { (url: URL) -> DirectoryListing in
            DirectoryListing(rootChildren: listings[url.normalizedPathKey] ?? [])
        }
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "SidebarLayoutTransitionTests")
        )
        preference.record { $0.layoutMode = .tree }
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: listing(currentDirectory).rows(),
            selection: selection,
            displayDefaults: preference,
            directoryLister: { url, _, _ in listing(url) },
            childrenLister: { url, _, _ in listings[url.normalizedPathKey] },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: currentFile)
        navigator.attach(to: host)
        return (navigator, host)
    }

    private func drainChildLoads(_ navigator: SidebarNavigator) async {
        await navigator.awaitSettled()
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }

    /// ツリーで sub を展開した状態を作る。
    private func expandSub(_ navigator: SidebarNavigator, _ fixture: Fixture) async {
        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.expandFolder(fixture.sub.normalizedPathKey, at: fixture.sub)
        await drainChildLoads(navigator)
        #expect(navigator.expandedFolderKeys.contains(fixture.sub.normalizedPathKey))
    }

    // MARK: - AC #1 往復での開閉状態の復元

    @Test("ツリー→リスト→ツリーの往復で開閉状態が同一に復元される")
    func roundTripPreservesExpansionState() async {
        let fixture = makeFixture("round-trip")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: nil, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        await expandSub(navigator, fixture)
        let savedKeys = navigator.expandedFolderKeys

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)
        #expect(navigator.fileListModel.layoutMode == .drillDown)

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)

        #expect(navigator.fileListModel.layoutMode == .tree)
        #expect(navigator.expandedFolderKeys == savedKeys)
        #expect(
            navigator.fileListModel.currentDirectory.normalizedPathKey
                == fixture.base.normalizedPathKey
        )
        // 復元された展開が行にも出ている。
        #expect(
            navigator.fileListModel.entries.map(\.url.lastPathComponent).contains("inner")
        )
    }

    // MARK: - AC #2 リストへの切り替えで選択の親フォルダーへ移る

    @Test("深い階層のファイルを選択した状態でリストへ切り替えると、その親がカレントになる")
    func switchToListMovesToSelectionParent() async {
        let fixture = makeFixture("to-list-selected")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: nil, currentFile: fixture.deepFile
        )
        defer { withExtendedLifetime(host) {} }
        await expandSub(navigator, fixture)
        navigator.expandFolder(fixture.inner.normalizedPathKey, at: fixture.inner)
        await drainChildLoads(navigator)
        navigator.fileListModel.selection = fixture.deepFile

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)

        #expect(navigator.fileListModel.layoutMode == .drillDown)
        #expect(
            navigator.fileListModel.currentDirectory.normalizedPathKey
                == fixture.inner.normalizedPathKey
        )
        #expect(
            navigator.fileListModel.selection?.normalizedPathKey
                == fixture.deepFile.normalizedPathKey
        )
    }

    @Test("ファイル未選択でリストへ切り替えると、カレントはルートのまま動かない")
    func switchToListWithoutSelectionStaysAtRoot() async {
        let fixture = makeFixture("to-list-unselected")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: nil, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        await expandSub(navigator, fixture)
        navigator.fileListModel.selection = nil

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)

        #expect(
            navigator.fileListModel.currentDirectory.normalizedPathKey
                == fixture.base.normalizedPathKey
        )
    }

    // MARK: - AC #3 root 配下からツリーへ戻ると root と選択位置までの経路が復元される

    @Test("リストで root 配下へ移動してからツリーへ戻すと、root と選択への経路が復元される")
    func returnToTreeRestoresRootAndRevealsSelection() async {
        let fixture = makeFixture("restore-reveal")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: nil, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        navigator.refreshFileList()
        await navigator.awaitSettled()

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)
        navigator.navigateToFolder(fixture.inner)
        await drainChildLoads(navigator)
        navigator.fileListModel.selection = fixture.deepFile
        let spy = SpyTableView()
        navigator.fileListModel.tableFocuser.tableView = spy

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)

        #expect(navigator.fileListModel.layoutMode == .tree)
        #expect(
            navigator.fileListModel.currentDirectory.normalizedPathKey
                == fixture.base.normalizedPathKey
        )
        // 選択(deep.mmd)までの経路 sub / inner が展開され、選択行が行配列に載る。
        #expect(navigator.expandedFolderKeys.contains(fixture.sub.normalizedPathKey))
        #expect(navigator.expandedFolderKeys.contains(fixture.inner.normalizedPathKey))
        let names = navigator.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains("deep.mmd"))
        #expect(
            navigator.fileListModel.selection?.normalizedPathKey
                == fixture.deepFile.normalizedPathKey
        )
        // 選択行を可視にするスクロールが要求されている。
        let deepRow = navigator.fileListModel.entries.firstIndex {
            $0.url.normalizedPathKey == fixture.deepFile.normalizedPathKey
        }
        #expect(spy.scrolledRows.last != nil)
        #expect(spy.scrolledRows.last == deepRow)
    }

    // MARK: - AC #4 root の外からツリーへ戻すと移動先が新しいルートになる

    @Test("リストで root の外へ移動してからツリーへ戻すと、移動先が新しいルートになる")
    func returnToTreeOutsideRootReroots() async {
        let fixture = makeFixture("reroot")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: nil, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        await expandSub(navigator, fixture)

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)
        navigator.navigateToFolder(fixture.outside)
        await drainChildLoads(navigator)

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)

        #expect(navigator.fileListModel.layoutMode == .tree)
        #expect(
            navigator.fileListModel.currentDirectory.normalizedPathKey
                == fixture.outside.normalizedPathKey
        )
        // 元の root の展開は別ツリーのものなので捨てられている。
        #expect(navigator.expandedFolderKeys.isEmpty)
    }

    // MARK: - AC #5 リスト中のフォルダー移動は展開を温存する

    @Test("リストモード中にフォルダーを移動しても、温存した展開は破棄されない")
    func listNavigationKeepsRetainedExpansion() async {
        let fixture = makeFixture("keep-on-navigate")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: nil, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        await expandSub(navigator, fixture)
        let savedKeys = navigator.expandedFolderKeys

        navigator.applyDisplayChange(.toggleLayoutMode)
        await drainChildLoads(navigator)
        navigator.navigateToFolder(fixture.sub)
        await drainChildLoads(navigator)

        #expect(navigator.expandedFolderKeys == savedKeys)
    }
}
