import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ウィンドウ層から見た提示対象(ADR 0002 段 1)を検証する。
/// ウィンドウは一覧を空で作って非同期に埋めるため、「一覧が届く前」は
/// フォルダー提示と判定してはならない。ここを取り違えると、起動直後の
/// あいだだけ印刷・検索・ズームが無効になる。
@Suite
@MainActor
struct ViewerWindowControllerPreviewTargetTests {
    private let file = URL(fileURLWithPath: "/mock/note.md")

    private func makeController() -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, contents: "# hi",
            defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerPreviewTargetTests")
        ).controller
    }

    @Test("一覧が届く前はフォルダー提示と判定しない")
    func doesNotReportFolderPreviewBeforeFirstListing() {
        let controller = makeController()
        defer { controller.close() }

        #expect(!controller.fileListModel.hasLoadedEntries)
        #expect(controller.fileListModel.previewTarget == .undetermined)
        #expect(!controller.isPreviewingFolder)
    }

    @Test("一覧が届いてフォルダー行が選ばれるとフォルダー提示になる")
    func reportsFolderPreviewForSelectedFolder() {
        let controller = makeController()
        defer { controller.close() }
        let folder = URL(fileURLWithPath: "/mock/sub")

        controller.fileListModel.entries = [
            FileListEntry(url: file, kind: .file),
            FileListEntry(url: folder, kind: .folder),
        ]
        controller.fileListModel.selection = folder

        #expect(controller.isPreviewingFolder)
        #expect(controller.fileListModel.previewTarget == .folder(folder))
    }

    @Test("フォルダー提示中は、ソース表示・行番号・ブックマークが実行されない")
    func blocksDocumentCommandsWhilePresentingFolder() {
        let controller = makeController()
        defer { controller.close() }
        let folder = URL(fileURLWithPath: "/mock/sub")
        controller.fileListModel.entries = [
            FileListEntry(url: file, kind: .file), FileListEntry(url: folder, kind: .folder),
        ]

        controller.fileListModel.selection = file
        let sourceModeBefore = controller.isSourceMode
        let lineNumbersBefore = controller.store.showLineNumbers
        let bookmarkedBefore = controller.isBookmarked

        controller.fileListModel.selection = folder
        #expect(!controller.capabilities.canToggleSourceMode)
        #expect(!controller.capabilities.canToggleLineNumbers)
        #expect(!controller.capabilities.canBookmark)

        // メニューを通らない経路(ツールバー・オーバーフロー)と同じく実処理を直接呼ぶ
        controller.setSourceMode(!sourceModeBefore)
        controller.toggleLineNumbers(nil)
        controller.toggleBookmark(nil)

        #expect(controller.isSourceMode == sourceModeBefore)
        #expect(controller.store.showLineNumbers == lineNumbersBefore)
        #expect(controller.isBookmarked == bookmarkedBefore)
    }

    @Test("一覧が届いた後にファイル行が選ばれていればフォルダー提示ではない")
    func reportsFilePreviewForSelectedFile() {
        let controller = makeController()
        defer { controller.close() }

        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file

        #expect(!controller.isPreviewingFolder)
        #expect(controller.fileListModel.previewTarget == .file)
    }
}
