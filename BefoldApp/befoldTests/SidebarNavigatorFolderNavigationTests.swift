@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// SidebarNavigator.navigateToFolder の選択ポリシー(ホーム上限ガード・子フォルダーへの
/// 移動で自動選択/自動オープンしない・親フォルダーへ戻ると直前の子フォルダーが選ばれる)を、
/// 実ディレクトリ列挙もフルウィンドウ生成も伴わずに検証する。実 FS の列挙結果自体は本質でないため、
/// directoryLister をディレクトリごとの固定エントリで差し替える
/// (前例: SidebarNavigatorBaseDirectoryTests)。移設元:
/// ViewerWindowControllerIntegrationTests.swift(navigateToFolderToParentWorks 等 6 テスト、旧 139-238 行)。
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
            hiddenFilesPreference: HiddenFilesPreference(
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

    @Test("子フォルダーへの移動では自動選択されない")
    func navigateToChildDoesNotAutoSelect() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-noselect")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let grandChild = sub.appendingPathComponent("grandchild", isDirectory: true)
        let child = sub.appendingPathComponent("child.mmd")
        // 選択候補になり得るファイル(child.mmd)があっても自動選択しないことを固定する。
        // フォルダーのみ(選択候補が無い)だと navigateToChildWithoutFilesClearsSelection と
        // 区別が付かなくなる。
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

        #expect(navigator.fileListModel.selection == nil)
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
}
