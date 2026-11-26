import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ウィンドウ層から見た提示対象(ADR 0002 / ADR 0013)を検証する。
///
/// 本文に何を出すかは窓の意図(`PresentationIntent`)が決め、サイドバーの選択や一覧の
/// 着地からは導かない。窓は文書を開いて生成されるので、一覧が届く前でも文書を出している
/// (印刷・検索・ズームが効く)。
@Suite
@MainActor
struct ViewerWindowControllerPreviewTargetTests {
    private let file = URL(fileURLWithPath: "/mock/note.md")
    private let folder = URL(fileURLWithPath: "/mock/sub")

    private func makeController() -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, contents: "# hi",
            defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerPreviewTargetTests")
        ).controller
    }

    @Test("生成直後は、一覧が届く前でも文書を提示している")
    func presentsDocumentBeforeFirstListing() {
        let controller = makeController()
        defer { controller.close() }

        #expect(!controller.fileListModel.hasLoadedEntries)
        #expect(controller.presentationIntent.target == .file)
        #expect(!controller.isPreviewingFolder)
    }

    @Test("利用者がフォルダー行を選ぶとフォルダー提示になる")
    func reportsFolderPreviewForSelectedFolder() {
        let controller = makeController()
        defer { controller.close() }

        controller.fileListDidSelectFolder(folder)

        #expect(controller.isPreviewingFolder)
        #expect(controller.presentationIntent.target == .folder(folder))
    }

    /// 選択はサイドバーの強調であって、本文は動かさない(ADR 0013)。切替後の同期や
    /// 一覧の着地がフォルダー行へ選択を書いても、本文がフォルダー一覧へ倒れてはならない。
    @Test("選択をフォルダー行へ書くだけでは、本文はフォルダー提示にならない")
    func selectionAloneDoesNotPresentFolder() {
        let controller = makeController()
        defer { controller.close() }
        controller.fileListModel.entries = [
            FileListEntry(url: file, kind: .file), FileListEntry(url: folder, kind: .folder),
        ]

        controller.fileListModel.selection = folder
        controller.fileListModel.selection = nil

        #expect(!controller.isPreviewingFolder)
    }

    @Test("フォルダー提示中は、ソース表示・行番号・ブックマークが実行されない")
    func blocksDocumentCommandsWhilePresentingFolder() {
        let controller = makeController()
        defer { controller.close() }
        let sourceModeBefore = controller.isSourceMode
        let lineNumbersBefore = controller.store.showLineNumbers
        let bookmarkedBefore = controller.isBookmarked

        controller.fileListDidSelectFolder(folder)
        #expect(!controller.capabilities.canToggleSourceMode)
        #expect(!controller.capabilities.canToggleLineNumbers)
        #expect(!controller.capabilities.canBookmark)

        // メニューを通らない経路(ツールバー・オーバーフロー)と同じく実処理を直接呼ぶ
        controller.setDisplayMode(sourceModeBefore ? .rendered : .source)
        controller.toggleLineNumbers(nil)
        controller.toggleBookmark(nil)

        #expect(controller.isSourceMode == sourceModeBefore)
        #expect(controller.store.showLineNumbers == lineNumbersBefore)
        #expect(controller.isBookmarked == bookmarkedBefore)
    }

    /// 開いている文書の行をもう一度選んだとき。切替は早期 return するが、本文には
    /// 文書を戻す(選択から導いていた頃と同じ見え方を保つ)。
    @Test("フォルダー提示中に開いている文書を選び直すと、文書の提示へ戻る")
    func reselectingOpenDocumentReturnsToDocument() {
        let controller = makeController()
        defer { controller.close() }
        controller.fileListDidSelectFolder(folder)

        controller.fileListDidSelectFile(file)

        #expect(!controller.isPreviewingFolder)
        #expect(controller.presentationIntent.target == .file)
    }
}
