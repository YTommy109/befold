@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// SidebarNavigator.navigateToFolder / refreshFileList の選択・rootDirectory ポリシー
/// (ホーム上限ガード・子フォルダーへ降りたら先頭行を選ぶがプレビューは一覧のまま・親フォルダーへ
/// 戻ると直前の子フォルダーが選ばれる・上位移動で rootDirectory が最上位へ更新される・
/// refreshFileList でフォルダー選択が保持される)を、実ディレクトリ列挙もフルウィンドウ
/// 生成も伴わずに検証する。実 FS の列挙結果自体は本質でないため、
/// directoryLister をディレクトリごとの固定エントリで差し替える
/// (前例: SidebarNavigatorBaseDirectoryTests)。移設元:
/// ViewerWindowControllerIntegrationTests.swift(navigateToFolderToParentWorks 等 6 テスト、旧 139-238 行)、
/// SidebarNavigatorIntegrationTests.swift(navigatingUpUpdatesRootDirectory /
/// refreshFileListPreservesFolderSelection、実 FS を使わず directoryLister スタブで検証可能と判明したため移設)。
@Suite
@MainActor
struct SidebarNavigatorFolderNavigationTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// directoryLister をディレクトリの pathKey で固定エントリを返すスタブに差し替えたナビゲーターを作る。
    /// entries に無いディレクトリを要求されたら空配列を返す(実 FS には一切アクセスしない)。
    private func makeNavigator(
        currentDirectory: URL,
        selection: URL?,
        listings: [String: [FileListEntry]]
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: listings[currentDirectory.normalizedPathKey] ?? [],
            selection: selection,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorFolderNavigationTests")
            ),
            directoryLister: { url, _, _ in listings[url.normalizedPathKey] ?? [] },
            resolveGitRoot: { _ in nil }
        )
        let host = SidebarNavigatorStubHost(
            currentFileURL: currentDirectory.appendingPathComponent("diagram.mmd")
        )
        navigator.attach(to: host)
        return (navigator, host)
    }

    @Test("navigateToFolder で親フォルダーへ移動できる")
    func navigateToFolderToParentWorks() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-parent")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let (navigator, host) = makeNavigator(
            currentDirectory: sub,
            selection: nil,
            listings: [tmp.normalizedPathKey: []]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(tmp)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.currentDirectory.standardizedFileURL == tmp.standardizedFileURL)
    }

    @Test("navigateToFolder はホームディレクトリより上には移動しない")
    func navigateToFolderRefusesAboveHomeDirectory() {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-refuse")
        let (navigator, host) = makeNavigator(currentDirectory: tmp, selection: nil, listings: [:])
        defer { withExtendedLifetime(host) {} }
        let before = navigator.fileListModel.currentDirectory
        let aboveHome = Self.home.deletingLastPathComponent()

        navigator.navigateToFolder(aboveHome)

        #expect(navigator.fileListModel.currentDirectory == before)
    }

    @Test("子フォルダーへ降りると一覧の先頭が選択される")
    func navigateToChildSelectsFirstEntry() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-first")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let grandChild = sub.appendingPathComponent("grandchild", isDirectory: true)
        let child = sub.appendingPathComponent("child.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [
                sub.normalizedPathKey: [
                    FileListEntry(url: grandChild, kind: .folder),
                    FileListEntry(url: child, kind: .file),
                ],
            ]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(sub)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.selection?.lastPathComponent == "grandchild")
    }

    @Test("先頭が選択されても、プレビューは移動先ディレクトリの一覧のままである")
    func navigateToChildKeepsPreviewOnDirectoryListing() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-listing")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let child = sub.appendingPathComponent("child.mmd")
        // 先頭がファイルでも、その中身をプレビューへ出してはならない(TASK-61 の挙動)。
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [sub.normalizedPathKey: [FileListEntry(url: child, kind: .file)]]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(sub)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.selection?.lastPathComponent == "child.mmd")
        #expect(navigator.fileListModel.previewTarget == .folder(sub))
    }

    @Test("降りた先で利用者が選び直すと、その行がプレビュー対象になる")
    func selectingAfterDescendingPresentsThatEntry() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-reselect")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let first = sub.appendingPathComponent("a.mmd")
        let second = sub.appendingPathComponent("b.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [
                sub.normalizedPathKey: [
                    FileListEntry(url: first, kind: .file),
                    FileListEntry(url: second, kind: .file),
                ],
            ]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(sub)
        await navigator.pendingListingTask?.value
        // 一覧に留める指示は選択の書き込みで倒れる。自動選択と同じ行を選び直しても同じ。
        navigator.fileListModel.selection = first

        #expect(navigator.fileListModel.previewTarget == .file)
    }

    @Test("親ナビゲーション行は自動選択の対象にしない")
    func navigateToChildSkipsParentNavigationRow() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-skipparent")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let child = sub.appendingPathComponent("child.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [
                sub.normalizedPathKey: [
                    FileListEntry(url: tmp, kind: .parentNavigation),
                    FileListEntry(url: child, kind: .file),
                ],
            ]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(sub)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.selection?.lastPathComponent == "child.mmd")
    }

    @Test("子フォルダーへの移動ではファイルが自動的に開かれない")
    func navigateToChildDoesNotAutoOpenFile() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-noopen")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let child = sub.appendingPathComponent("child.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [sub.normalizedPathKey: [FileListEntry(url: child, kind: .file)]]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(sub)
        await navigator.pendingListingTask?.value

        #expect(host.performFileSwitchCallCount == 0)
    }

    @Test("ファイルのない子フォルダーへの移動では何も選択されない")
    func navigateToChildWithoutFilesClearsSelection() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-empty")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [sub.normalizedPathKey: []]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(sub)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.selection == nil)
        #expect(navigator.fileListModel.previewTarget == .folder(sub))
    }

    @Test("親フォルダーへの移動では直前の子フォルダーが選択される")
    func navigateToParentSelectsPreviousChild() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-parentselect")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let (navigator, host) = makeNavigator(
            currentDirectory: sub,
            selection: nil,
            listings: [tmp.normalizedPathKey: [FileListEntry(url: sub, kind: .folder)]]
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(tmp)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.selection?.lastPathComponent == "sub")
    }

    @Test("親ディレクトリへ移動すると rootDirectory が最上位に更新される")
    func navigatingUpUpdatesRootDirectory() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-root")
        let level1 = tmp.appendingPathComponent("level1", isDirectory: true)
        let level2 = level1.appendingPathComponent("level2", isDirectory: true)
        let level3 = level2.appendingPathComponent("level3", isDirectory: true)
        let (navigator, host) = makeNavigator(
            currentDirectory: level3,
            selection: nil,
            listings: [
                level2.normalizedPathKey: [],
                level3.normalizedPathKey: [],
            ]
        )
        defer { withExtendedLifetime(host) {} }

        // 初期状態では rootDirectory はファイルの親ディレクトリ(level3)。
        #expect(navigator.fileListModel.rootDirectory.path == level3.path)

        // level2 へ上に移動すると、そこが新たな最上位として rootDirectory に反映される。
        navigator.navigateToFolder(level2)
        await navigator.pendingListingTask?.value
        #expect(navigator.fileListModel.rootDirectory.path == level2.path)

        // level3 へ戻っても、既に到達した最上位(level2)は保持される。
        navigator.navigateToFolder(level3)
        await navigator.pendingListingTask?.value
        #expect(navigator.fileListModel.rootDirectory.path == level2.path)
    }

    @Test("フォルダーを選択した状態で refreshFileList してもフォルダー選択が保持される")
    func refreshFileListPreservesFolderSelection() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-refresh")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        // ファイルではなくフォルダーをサイドバーで選択した状態を再現する(host.currentFileURL とは無関係)。
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: sub,
            listings: [tmp.normalizedPathKey: [FileListEntry(url: sub, kind: .folder)]]
        )
        defer { withExtendedLifetime(host) {} }

        // 他アプリへ切り替えて戻ってきた際に windowDidBecomeKey から呼ばれる処理を再現する。
        navigator.refreshFileList()
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.selection == sub)
    }
}
