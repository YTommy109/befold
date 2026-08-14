@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 戻る/進む履歴が **提示対象(ファイル / フォルダー一覧)ごと** 復元されることを検証する
/// (TASK-468)。
///
/// `ViewerWindowControllerHistoryTests` はファイル↔ファイルの往復だけを見ており、
/// 履歴がフォルダー提示を跨ぐ場合を押さえられない。フォルダー提示を作るには
/// 「一覧にどんな行が並ぶか」を制御する必要があるが、ウィンドウ生成を伴うあちらの
/// フィクスチャは実ファイルシステムを列挙するため行を組み立てられない。ここでは
/// `SidebarNavigatorFolderNavigationTests` と同じ directoryLister スタブを使い、
/// 実 FS に触れずに履歴の記録と適用だけを見る。
@Suite
@MainActor
struct SidebarNavigatorHistoryTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// directoryLister をディレクトリの pathKey で固定エントリを返すスタブに差し替えた
    /// ナビゲーターを作る(前例: SidebarNavigatorFolderNavigationTests)。
    private func makeNavigator(
        currentDirectory: URL,
        selection: URL?,
        currentFile: URL,
        listings: [String: [FileListEntry]]
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let listing = { (url: URL) -> DirectoryListing in
            DirectoryListing(rootChildren: listings[url.normalizedPathKey] ?? [])
        }
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: listing(currentDirectory).rows(),
            selection: selection,
            displayDefaults: SidebarDisplayDefaults(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorHistoryTests")
            ),
            directoryLister: { url, _, _ in listing(url) },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: currentFile)
        navigator.attach(to: host)
        return (navigator, host)
    }

    /// tmp/(sub/(child.mmd), a.mmd) の 3 階層。フォルダー提示を作るには
    /// 「上へ移動 = 直前の子フォルダーが選ばれる」経路が要るので、親子 2 段を用意する。
    private struct Fixture {
        let tmp: URL
        let sub: URL
        let child: URL
        let sibling: URL
    }

    private func makeFixture(_ name: String) -> Fixture {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorHistoryTests-\(name)")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        return Fixture(
            tmp: tmp,
            sub: sub,
            child: sub.appendingPathComponent("child.mmd"),
            sibling: tmp.appendingPathComponent("a.mmd")
        )
    }

    private func listings(_ fixture: Fixture) -> [String: [FileListEntry]] {
        [
            fixture.tmp.normalizedPathKey: [
                FileListEntry(url: fixture.sub, kind: .folder),
                FileListEntry(url: fixture.sibling, kind: .file),
            ],
            fixture.sub.normalizedPathKey: [FileListEntry(url: fixture.child, kind: .file)],
        ]
    }

    @Test("フォルダー一覧を出していたエントリへ戻ると、そのフォルダー一覧が復元される")
    func goingBackToFolderEntryRestoresFolderListing() async {
        let fixture = makeFixture("folder-entry")
        let (navigator, host) = makeNavigator(
            currentDirectory: fixture.tmp,
            selection: fixture.sub,
            currentFile: fixture.sibling,
            listings: listings(fixture)
        )
        defer { withExtendedLifetime(host) {} }
        // 「tmp でフォルダー sub を選んで一覧を出している」状態を履歴へ積む。
        navigator.recordHistory()
        #expect(navigator.fileListModel.previewTarget == .folder(fixture.sub))

        // sub へ降りてファイルを開き(履歴が 1 つ進む)、そこから戻る。
        navigator.navigateToFolder(fixture.sub)
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.previewTarget == .file)

        navigator.navigateHistory(by: -1)
        await navigator.awaitSettled()

        // 戻り先は「フォルダー sub の一覧」であってファイルではない。
        #expect(navigator.fileListModel.previewTarget == .folder(fixture.sub))
        #expect(navigator.fileListModel.selection?.lastPathComponent == "sub")
    }

    /// **このケースは修正前のコードでも通る**(実測)。ドリルダウン表示では、着地側の
    /// 既定フォールバック(選択が一覧に残っていなければ開いている文書を選び直す)が
    /// 結果的に救うため。報告された症状そのものの経路は握れていないが、AC #1/#2 の
    /// 振る舞いを固定しておく意味で残す。回帰を検知するのは上下 2 つのテスト。
    @Test("フォルダー提示を跨いで戻り、ファイルのエントリに到達するとそのファイルが提示される")
    func goingBackPastFolderEntryReachesFileEntry() async {
        let fixture = makeFixture("past-folder")
        let (navigator, host) = makeNavigator(
            currentDirectory: fixture.sub,
            selection: fixture.child,
            currentFile: fixture.child,
            listings: listings(fixture)
        )
        defer { withExtendedLifetime(host) {} }
        // 1) sub で child.mmd を提示している状態を積む。
        navigator.recordHistory()
        // 2) 親 tmp へ上がる。直前の子フォルダー sub が選ばれ、提示はフォルダー一覧になる。
        navigator.navigateToFolder(fixture.tmp)
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.previewTarget == .folder(fixture.sub))

        // 3) 戻ると 1) のファイル提示に戻る(フォルダー一覧が残り続けない)。
        navigator.navigateHistory(by: -1)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.previewTarget == .file)
        #expect(navigator.fileListModel.selection?.lastPathComponent == "child.mmd")
        #expect(host.currentFileURL.lastPathComponent == "child.mmd")
    }

    @Test("履歴の適用は moveCurrentDirectory を通り、離れるフォルダーの選択を記憶する")
    func applyingHistoryRemembersSelectionOfDirectoryLeftBehind() async {
        let fixture = makeFixture("selection-memory")
        let note = fixture.sub.appendingPathComponent("note.mmd")
        var listings = listings(fixture)
        listings[fixture.sub.normalizedPathKey] = [
            FileListEntry(url: fixture.child, kind: .file),
            FileListEntry(url: note, kind: .file),
        ]
        let (navigator, host) = makeNavigator(
            currentDirectory: fixture.tmp,
            selection: fixture.sibling,
            currentFile: fixture.sibling,
            listings: listings
        )
        defer { withExtendedLifetime(host) {} }
        navigator.recordHistory()
        navigator.navigateToFolder(fixture.sub)
        await navigator.awaitSettled()
        // sub の中で 2 つめのファイルを選び直す(クリックと同じく選択を書くだけ)。
        navigator.fileListModel.selection = note

        // 戻る。ディレクトリを跨ぐ適用が moveCurrentDirectory を通らないと、
        // 離れる sub の選択が記憶されない(currentDirectory への直接代入では
        // selectionMemory.remember が素通りする / TASK-465)。
        navigator.navigateHistory(by: -1)
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == fixture.tmp.normalizedPathKey)

        // 記憶されていれば、sub へ入り直したときに先頭行ではなく note.mmd が選ばれる。
        navigator.navigateToFolder(fixture.sub)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.selection?.lastPathComponent == "note.mmd")
    }
}
