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
        let folderWindow = fixture.manager.openFolder(tmp.url, options: CLIOpenOptions())
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

        let folderWindow = fixture.manager.openFolder(dir, options: options)
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

        let folderWindow = fixture.manager.openFolder(dir, options: options)
        defer { folderWindow.close() }

        #expect(folderWindow.sidebarCollapsible?.resolvedSidebarCollapsed == expectedCollapsed)
    }
}
