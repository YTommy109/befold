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
    private static let home = FileManager.default.temporaryDirectory

    /// directoryLister をディレクトリの pathKey で固定エントリを返すスタブに差し替えたナビゲーターを作る。
    /// entries に無いディレクトリを要求されたら空配列を返す(実 FS には一切アクセスしない)。
    private func makeNavigator(
        currentDirectory: URL,
        selection: URL?,
        currentFile: URL? = nil,
        listings: [String: [FileListEntry]]
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let listing = { (url: URL) -> DirectoryListing in
            DirectoryListing(rootChildren: listings[url.normalizedPathKey] ?? [])
        }
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: listing(currentDirectory).rows(),
            selection: selection,
            home: FileManager.default.temporaryDirectory,
            displayDefaults: SidebarDisplayDefaults(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorFolderNavigationTests")
            ),
            directoryLister: { url, _, _ in listing(url) },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(
            currentFileURL: currentFile ?? currentDirectory.appendingPathComponent("diagram.mmd")
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

        navigator.navigateToFolder(tmp, presentingFolder: { _ in })
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.currentDirectory.standardizedFileURL == tmp.standardizedFileURL)
    }

    @Test("navigateToFolder はホームディレクトリより上には移動しない")
    func navigateToFolderRefusesAboveHomeDirectory() {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-refuse")
        let (navigator, host) = makeNavigator(currentDirectory: tmp, selection: nil, listings: [:])
        defer { withExtendedLifetime(host) {} }
        let before = navigator.fileListModel.currentDirectory
        let aboveHome = Self.home.deletingLastPathComponent()

        navigator.navigateToFolder(aboveHome, presentingFolder: { _ in })

        #expect(navigator.fileListModel.currentDirectory == before)
    }

    /// 先頭がファイルでもフォルダーでも、入ったフォルダー自身の一覧を出す(ADR 0013 決定 5)。
    /// かつては先頭行を自動で選び、ファイルなら開き、フォルダーならその一覧を出していた
    /// (TASK-310)。一覧の着地を待たずに出すことも測る(遅い列挙の間に前のファイルが残らない)。
    @Test("子フォルダーへ入ると、着地を待たずにそのフォルダーの一覧を出し、何も選ばず何も開かない", arguments: [
        FileListEntry.Kind.file, .folder,
    ])
    func navigateToChildPresentsItsOwnListing(headKind: FileListEntry.Kind) async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-enter-\(headKind)")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let head = sub.appendingPathComponent(
            headKind == .file ? "child.mmd" : "grandchild",
            isDirectory: headKind == .folder
        )
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [sub.normalizedPathKey: [FileListEntry(url: head, kind: headKind)]]
        )
        defer { withExtendedLifetime(host) {} }

        var presented: [URL] = []
        navigator.navigateToFolder(sub, presentingFolder: { presented.append($0) })
        #expect(presented.map(\.normalizedPathKey) == [sub.normalizedPathKey], "着地を待っている")
        await navigator.awaitSettled()

        #expect(presented.map(\.normalizedPathKey) == [sub.normalizedPathKey])
        #expect(navigator.fileListModel.selection == nil)
        #expect(host.performFileSwitchCallCount == 0)
    }

    @Test("親フォルダーへ上がると、直前にいた子フォルダーではなく移動先の一覧を出す")
    func navigateToParentPresentsParentListing() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-parent")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let (navigator, host) = makeNavigator(
            currentDirectory: sub,
            selection: nil,
            listings: [tmp.normalizedPathKey: [FileListEntry(url: sub, kind: .folder)]]
        )
        defer { withExtendedLifetime(host) {} }

        var presented: [URL] = []
        navigator.navigateToFolder(tmp, presentingFolder: { presented.append($0) })
        await navigator.awaitSettled()

        #expect(presented.map(\.normalizedPathKey) == [tmp.normalizedPathKey])
        #expect(navigator.fileListModel.selection == nil)
    }

    @Test("再訪したフォルダーでも、前回の選択を復元してファイルを開くことはしない")
    func revisitingFolderDoesNotRestorePreviousSelection() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-revisit")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let note = sub.appendingPathComponent("note.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            listings: [
                tmp.normalizedPathKey: [FileListEntry(url: sub, kind: .folder)],
                sub.normalizedPathKey: [FileListEntry(url: note, kind: .file)],
            ]
        )
        defer { withExtendedLifetime(host) {} }
        navigator.navigateToFolder(sub, presentingFolder: { _ in })
        await navigator.awaitSettled()
        navigator.fileListModel.selection = note
        navigator.navigateToFolder(tmp, presentingFolder: { _ in })
        await navigator.awaitSettled()

        navigator.navigateToFolder(sub, presentingFolder: { _ in })
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.selection == nil)
        #expect(host.performFileSwitchCallCount == 0)
    }

    /// 入った後の取り直し(窓がキーになるたびに走る)は、開いている文書を選び直さない。
    /// 選び直すと提示していない行が光り、文書が外にあればリストへの切り替えで
    /// カレントがその親へ跳ぶ(ADR 0013 決定 3)。
    @Test("フォルダーに入った後の取り直しと表示形式の切り替えで、開いている文書へ選択もカレントも寄らない", arguments: [
        true, false,
    ])
    func refreshAfterEnteringKeepsFolderPresentation(documentInside: Bool) async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorFolderNavigationTests-refresh-\(documentInside)")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let document = (documentInside ? sub : tmp).appendingPathComponent("doc.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: tmp,
            selection: nil,
            currentFile: document,
            listings: [sub.normalizedPathKey: [FileListEntry(url: sub.appendingPathComponent("x.mmd"), kind: .file)]]
        )
        defer { withExtendedLifetime(host) {} }
        navigator.navigateToFolder(sub, presentingFolder: { host.presentedTarget = .folder($0) })
        await navigator.awaitSettled()

        navigator.refreshFileList()
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.selection == nil)

        navigator.applyDisplayChange(.toggleLayoutMode)
        await navigator.awaitSettled()
        navigator.applyDisplayChange(.toggleLayoutMode)
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == sub.normalizedPathKey)
        #expect(navigator.fileListModel.selection == nil)
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
        navigator.navigateToFolder(level2, presentingFolder: { _ in })
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.rootDirectory.path == level2.path)

        // level3 へ戻っても、既に到達した最上位(level2)は保持される。
        navigator.navigateToFolder(level3, presentingFolder: { _ in })
        await navigator.awaitSettled()
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
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.selection == sub)
    }
}
