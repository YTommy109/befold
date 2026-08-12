import AppKit
@testable import befold
import BefoldKit
import Foundation
import Testing

/// CLI から転送されたブックマーク追加(`befold --bookmark <path>`)を
/// ストアと開いているウィンドウのツールバーへ反映することを検証する。
/// コントローラ生成は MockedViewerWindowManager 経由でモック化しているため実 FS を踏まない。
@Suite
@MainActor
struct ViewerWindowManagerBookmarkTests {
    private let file = URL(fileURLWithPath: "/mock/first.mmd")
    private let otherFile = URL(fileURLWithPath: "/mock/second.md")

    @Test("CLI からのブックマーク追加はストアと表示中ウィンドウのツールバーへ即座に反映される")
    func addBookmarksUpdatesStoreAndOpenWindowToolbar() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "CLIBookmarkToolbarRefresh")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        let toolbar = try #require(controller.window?.toolbar)
        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("bookmark") })
        let button = try #require(liveItem.view as? NSButton)
        #expect(button.contentTintColor == nil)

        fixture.manager.display.addBookmarks(for: [file])

        #expect(fixture.bookmarkStore.isBookmarked(file))
        #expect(button.contentTintColor == .controlAccentColor)
    }

    /// 開けなくなったブックマークを外す唯一の個別経路(issue #485)。
    @Test("ブックマーク済みのファイルが見つからないときは、外す操作を添えて通知する")
    func offersBookmarkRemovalWhenBookmarkedFileIsMissing() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "MissingBookmarkAlert")
        defer { fixture.closeAll() }
        let gone = URL(fileURLWithPath: "/mock/deleted-worktree/gone.md")
        fixture.bookmarkStore.add(gone)

        #expect(fixture.manager.openViewer(for: gone) == nil)

        #expect(fixture.fileNotFoundPresentations.presentedURLs == [gone])
        let remove = try #require(fixture.fileNotFoundPresentations.lastRemoveBookmarkAction)
        remove()
        #expect(!fixture.bookmarkStore.isBookmarked(gone))
    }

    /// ブックマークしていないファイルにまで「ブックマークから削除」を出すと、押しても
    /// 何も起きないボタンになる。
    @Test("ブックマークしていないファイルが見つからない場合は外す操作を添えない")
    func omitsBookmarkRemovalForUnbookmarkedMissingFile() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "MissingUnbookmarkedAlert")
        defer { fixture.closeAll() }
        let gone = URL(fileURLWithPath: "/mock/deleted-worktree/gone.md")

        #expect(fixture.manager.openViewer(for: gone) == nil)

        #expect(fixture.fileNotFoundPresentations.presentedURLs == [gone])
        #expect(fixture.fileNotFoundPresentations.lastRemoveBookmarkAction == nil)
    }

    @Test("表示中でないファイルのブックマーク追加は開いているウィンドウのアイコンを変えない")
    func addBookmarksForUnrelatedFileLeavesToolbarUntouched() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "CLIBookmarkUnrelated")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        let toolbar = try #require(controller.window?.toolbar)
        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("bookmark") })
        let button = try #require(liveItem.view as? NSButton)

        fixture.manager.display.addBookmarks(for: [otherFile])

        #expect(fixture.bookmarkStore.isBookmarked(otherFile))
        #expect(button.contentTintColor == nil)
    }
}
