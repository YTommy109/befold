import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// ディレクトリを開くと、ファイルを開かずにその一覧を出す(ADR 0013 決定 5 / TASK-930.4)。
/// ディレクトリ判定は実ファイルシステムを通す(`DirectoryLister.isDirectory`)。
@Suite
@MainActor
struct DocumentOpenerFolderTests {
    /// 中身のある・無いの両方で、文書の窓を作らずフォルダーの一覧を出す。空でもアラートにしない。
    @Test("ディレクトリを開くと、ファイルを開かずに一覧を出す", testTimeLimit(), arguments: [true, false])
    func openingDirectoryPresentsListing(hasFile: Bool) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = hasFile ? try tmp.file(named: "first.md", contents: "fixture") : nil
        let fixture = MockedViewerWindowManager(files: file.map { [$0] } ?? [], directories: [tmp.url])
        defer { fixture.closeAll() }
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })

        await opener.openViewer(for: tmp.url).value

        #expect(fixture.manager.allControllers.isEmpty, "ディレクトリの中のファイルを開いた")
        let folderWindow = try #require(fixture.manager.blankTabs.controllers.first)
        defer { folderWindow.close() }
        #expect(folderWindow.presentationIntent.target == .folder(tmp.url))
        #expect(folderWindow.presentedTarget == .folder(tmp.url))
        #expect(folderWindow.window?.title == tmp.url.lastPathComponent)
        #expect(folderWindow.sidebarDirectory == tmp.url)
    }

    /// 一覧の窓の中でフォルダーに入ったら、その一覧へ移る。文書には置き換わらない。
    @Test("フォルダーの窓でサブフォルダーに入ると、その一覧を出す", testTimeLimit())
    func navigatingInFolderWindowPresentsDestination() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let inner = try tmp.file(atPath: "sub/inner.md", contents: "fixture")
        let sub = inner.deletingLastPathComponent()
        let fixture = MockedViewerWindowManager(files: [inner], directories: [tmp.url, sub])
        defer { fixture.closeAll() }
        let folderWindow = fixture.manager.blankTabs.openFolder(
            tmp.url,
            options: CLIOpenOptions(),
            disposition: .currentTab,
            relativeTo: nil
        )
        defer { folderWindow.close() }
        let navigator = try #require(folderWindow.inheritableSidebar)

        folderWindow.fileListDidRequestNavigation(to: sub)
        await navigator.awaitSettled()

        #expect(folderWindow.presentationIntent.target == .folder(sub))
        #expect(folderWindow.window?.title == "sub")
        #expect(!folderWindow.isClosed)
        #expect(fixture.manager.allControllers.isEmpty)
    }

    /// 文書タブと同じく、サイドバーでフォルダー行を選ぶとその一覧を出す。
    @Test("空タブのサイドバーでフォルダー行を選ぶと、その一覧を出す")
    func selectingFolderRowInBlankPresentsListing() throws {
        let origin = URL(fileURLWithPath: "/mock/folder/origin.md")
        let sub = URL(fileURLWithPath: "/mock/folder/sub")
        let fixture = MockedViewerWindowManager(files: [origin], directories: [sub])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        #expect(blank.presentedTarget == nil)

        blank.fileListDidSelectFolder(sub)

        #expect(blank.presentedTarget == .folder(sub))
        #expect(blank.window?.title == "sub")
    }

    /// CLI の並び順・不可視ファイルは、この窓限りの上書き。保存された既定値は書き換えない。
    @Test("フォルダーの窓は CLI の表示オプションを窓単位で受け取る")
    func folderWindowAppliesCLIOverridesLocally() throws {
        let dir = URL(fileURLWithPath: "/mock/folder")
        let fixture = MockedViewerWindowManager(files: [], directories: [dir])
        defer { fixture.closeAll() }
        var options = CLIOpenOptions()
        options.showHiddenFiles = true

        let folderWindow = fixture.manager.blankTabs.openFolder(
            dir,
            options: options,
            disposition: .currentTab,
            relativeTo: nil
        )
        defer { folderWindow.close() }

        let navigator = try #require(folderWindow.inheritableSidebar)
        #expect(navigator.fileListModel.display.showHiddenFiles)
        #expect(!fixture.displayDefaults.settings.showHiddenFiles)
    }

    /// ディレクトリを開いたのでサイドバーは既定で出す。`--no-sidebar` があればそちらが勝つ。
    /// 最後の開閉操作は逆の値にしておき、それに引きずられていないことを測る。
    @Test("フォルダーの窓のサイドバーは既定で開き、--no-sidebar なら閉じる", arguments: [nil, false] as [Bool?])
    func folderWindowSidebarVisibility(showSidebar: Bool?) {
        let dir = URL(fileURLWithPath: "/mock/folder")
        let fixture = MockedViewerWindowManager(files: [], directories: [dir])
        defer { fixture.closeAll() }
        let expectedCollapsed = showSidebar == false
        fixture.sidebarState.recordToggle(!expectedCollapsed)
        var options = CLIOpenOptions()
        options.showSidebar = showSidebar

        let folderWindow = fixture.manager.blankTabs.openFolder(
            dir,
            options: options,
            disposition: .currentTab,
            relativeTo: nil
        )
        defer { folderWindow.close() }

        #expect(folderWindow.sidebarCollapsible?.resolvedSidebarCollapsed == expectedCollapsed)
    }

    /// 一覧の窓には文書が無いので、開いているフォルダーが消えたら空タブの画面へ戻す
    /// (TASK-930.7。文書タブは開いている文書へ戻る)。
    @Test("ディレクトリを開いた窓は、そのディレクトリが消えるとキーに戻ったときに空タブの画面になる")
    func vanishedFolderFallsBackToBlankScreen() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let folder = tmp.url.appendingPathComponent("listed", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = MockedViewerWindowManager(files: [], directories: [tmp.url, folder])
        defer { fixture.closeAll() }
        let folderWindow = fixture.manager.blankTabs.openFolder(
            folder,
            options: CLIOpenOptions(),
            disposition: .currentTab,
            relativeTo: nil
        )
        defer { folderWindow.close() }
        #expect(folderWindow.presentedTarget == .folder(folder))
        try FileManager.default.removeItem(at: folder)

        folderWindow.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        #expect(folderWindow.presentedTarget == nil)
        #expect(folderWindow.window?.title == String(localized: "menu.file.newTab", bundle: .l10n))
    }

    // MARK: - Reuse and options (TASK-930.8)

    /// git 取得が受けた比較基準を記録する。状態は返さない(基準が届いたかだけを測る)。
    private final class TargetRecordingReader: GitStatusReading, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [GitComparisonTarget] = []

        var targets: [GitComparisonTarget] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func indexFingerprint(forRepositoryAt _: URL) -> Date? {
            nil
        }

        func status(forRepositoryAt _: URL, target: GitComparisonTarget) -> GitStatusSnapshot? {
            lock.lock(); recorded.append(target); lock.unlock()
            return nil
        }
    }

    /// 同じディレクトリをもう一度開くと、既存の一覧の窓を前面に出す。新しい窓は作らない。
    /// 修正前は開くたびに一覧の窓が増えた。
    @Test("同じディレクトリをもう一度開くと、既存の一覧の窓を再利用する", testTimeLimit())
    func reopeningSameDirectoryReusesFolderWindow() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fixture = MockedViewerWindowManager(files: [], directories: [tmp.url])
        defer { fixture.closeAll() }
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })

        await opener.openViewer(for: tmp.url).value
        await opener.openViewer(for: tmp.url).value

        defer { fixture.manager.blankTabs.controllers.forEach { $0.close() } }
        #expect(fixture.manager.blankTabs.controllers.count == 1)
    }

    /// 開き方ごとの規則は文書の窓と同じ表(`ViewerWindowOpenPolicy.reusableWindow`)を通る。
    /// 手前のタブ扱いなら再利用、新しい窓(`--new-window`)なら常に新しく開く。
    @Test("一覧の窓の再利用は開き方に従う", arguments: [(OpenDisposition.currentTab, 1), (.newWindow, 2)])
    func folderWindowReuseFollowsDisposition(disposition: OpenDisposition, expectedCount: Int) {
        let dir = URL(fileURLWithPath: "/mock/folder")
        let fixture = MockedViewerWindowManager(files: [], directories: [dir])
        defer { fixture.closeAll() }
        let first = fixture.manager.blankTabs.openFolder(
            dir,
            options: CLIOpenOptions(),
            disposition: .currentTab,
            relativeTo: nil
        )

        let second = fixture.manager.blankTabs.openFolder(
            dir,
            options: CLIOpenOptions(),
            disposition: disposition,
            relativeTo: nil
        )

        defer { fixture.manager.blankTabs.controllers.forEach { $0.close() } }
        #expect(fixture.manager.blankTabs.controllers.count == expectedCount)
        #expect((first === second) == (expectedCount == 1))
    }

    /// `--compare` は一覧の窓の比較基準にも当たる。プロパティではなく、git 取得が受けた基準で測る。
    @Test("--compare はディレクトリの窓の git 取得の比較基準になる", testTimeLimit())
    func compareAppliesToFolderWindowGitFetch() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fixture = MockedViewerWindowManager(files: [], directories: [tmp.url])
        defer { fixture.closeAll() }
        let reader = TargetRecordingReader()
        fixture.manager.gitStatusStore = GitStatusStore(reader: reader, resolveRepositoryRoot: { _ in tmp.url })
        var options = CLIOpenOptions()
        options.comparisonTarget = .head

        let folderWindow = fixture.manager.blankTabs.openFolder(
            tmp.url, options: options, disposition: .currentTab, relativeTo: nil
        )
        defer { folderWindow.close() }
        let navigator = try #require(folderWindow.inheritableSidebar)
        await navigator.awaitSettled()

        #expect(reader.targets.contains(.head), "git 取得が受けた基準: \(reader.targets)")
    }

    /// 再利用した窓にも CLI の表示オプションを当てる(黙って捨てない / TASK-413)。
    @Test("再利用した一覧の窓にも CLI の表示オプションが当たる")
    func reusedFolderWindowReceivesCLIOptions() throws {
        let dir = URL(fileURLWithPath: "/mock/folder")
        let fixture = MockedViewerWindowManager(files: [], directories: [dir])
        defer { fixture.closeAll() }
        let folderWindow = fixture.manager.blankTabs.openFolder(
            dir,
            options: CLIOpenOptions(),
            disposition: .currentTab,
            relativeTo: nil
        )
        defer { fixture.manager.blankTabs.controllers.forEach { $0.close() } }
        var options = CLIOpenOptions()
        options.showHiddenFiles = true
        options.comparisonTarget = .head

        fixture.manager.blankTabs.openFolder(dir, options: options, disposition: .currentTab, relativeTo: nil)

        let navigator = try #require(folderWindow.inheritableSidebar)
        #expect(navigator.fileListModel.display.showHiddenFiles)
        #expect(folderWindow.comparisonTarget == .head)
    }

    // MARK: - Open elsewhere (TASK-930.8)

    enum ElsewhereSource: String, CaseIterable {
        case documentWindow, folderWindow
    }

    /// サイドバーのフォルダー行の「新しいタブ/ウィンドウで開く」は、そのフォルダーの一覧の窓を
    /// 開く。修正前はフォルダーの URL で文書の窓を作っていた(テストの読み手はディレクトリでも
    /// 存在すると答えるため)。新しいタブは起点のタブになる。
    @Test("フォルダー行を別の場所で開くと、そのフォルダーの一覧の窓になる", arguments: ElsewhereSource.allCases, [OpenDisposition.newTab, .newWindow])
    func openingFolderRowElsewherePresentsListing(source: ElsewhereSource, disposition: OpenDisposition) throws {
        let base = URL(fileURLWithPath: "/mock/base")
        let doc = base.appendingPathComponent("a.md")
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let fixture = MockedViewerWindowManager(files: [doc], directories: [base, sub])
        defer { fixture.closeAll() }
        defer { fixture.manager.blankTabs.controllers.forEach { $0.close() } }
        let sourceWindow: NSWindow
        switch source {
        case .documentWindow:
            let controller = try #require(fixture.manager.openViewer(for: doc))
            sourceWindow = try #require(controller.window)
            controller.fileListDidRequestOpenElsewhere(sub, disposition: disposition)
        case .folderWindow:
            let folder = fixture.manager.blankTabs.openFolder(
                base,
                options: CLIOpenOptions(),
                disposition: .currentTab,
                relativeTo: nil
            )
            sourceWindow = try #require(folder.window)
            folder.fileListDidRequestOpenElsewhere(sub, disposition: disposition)
        }

        let opened = try #require(fixture.manager.blankTabs.controllers.first { $0.presentedTarget == .folder(sub) })
        #expect(fixture.manager.allControllers.count == (source == .documentWindow ? 1 : 0), "フォルダーで文書の窓を作った")
        let sharesTabGroup = opened.window?.tabGroup != nil && opened.window?.tabGroup === sourceWindow.tabGroup
        #expect(sharesTabGroup == (disposition == .newTab))
    }
}
