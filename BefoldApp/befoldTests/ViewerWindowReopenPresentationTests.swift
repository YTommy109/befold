@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 窓の外から開く経路(CLI・Finder・最近使った項目)で、本文がフォルダー一覧に
/// 残らないことを検証する(ADR 0013 / TASK-930.2)。
///
/// 開き直し(すでに窓のあるファイルを開く)は `ViewerWindowManager.openViewer` の再利用
/// ブロックに集まる。そこが同じ URL への切り替え(`switchFile(to:)`)を通るので、
/// フォルダー一覧を出していた窓でも文書の提示へ戻る。
@Suite
@MainActor
struct ViewerWindowReopenPresentationTests {
    private let file = URL(fileURLWithPath: "/mock/reopen/doc.md")
    private let other = URL(fileURLWithPath: "/mock/reopen/other.md")
    private let folder = URL(fileURLWithPath: "/mock/reopen/sub", isDirectory: true)

    @Test("フォルダー一覧を出している窓で、開いている文書を開き直すと文書の提示へ戻る")
    func reopeningOpenDocumentLeavesFolderListing() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ReopenPresentation.reopen")
        defer { fixture.closeAll() }
        let controller = try #require(fixture.manager.openViewer(for: file))
        controller.fileListDidSelectFolder(folder)
        controller.fileListModel.selection = folder
        #expect(controller.isPreviewingFolder)

        let reopened = fixture.manager.openViewer(for: file)

        #expect(reopened === controller)
        #expect(!controller.isPreviewingFolder)
        // サイドバーも文書へ合わせる(強調が開いている文書の行へ戻る)。
        #expect(controller.fileListModel.selection?.normalizedPathKey == file.normalizedPathKey)
    }

    @Test("文書を出している窓で開き直しても、提示は変わらず再同期も起きない")
    func reopeningWhileShowingDocumentIsNoOp() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ReopenPresentation.noop")
        defer { fixture.closeAll() }
        let controller = try #require(fixture.manager.openViewer(for: file))
        let historyCount = controller.navigationHistory.entries.count
        var changes = 0
        let original = controller.presentationIntent.onChange
        controller.presentationIntent.onChange = { changes += 1; original?() }

        fixture.manager.openViewer(for: file)

        #expect(changes == 0)
        #expect(controller.navigationHistory.entries.count == historyCount)
    }

    /// 新しいタブは元の窓の一覧を出発点に引き継ぐ。新しいファイルがその一覧に無くても、
    /// 窓は生成時から文書を出しているので、一覧の着地を待つ間にフォルダー一覧へ倒れない。
    @Test("元の窓の一覧に無いファイルを新しいタブで開いても、本文はフォルダー一覧にならない")
    func newTabWithInheritedListingPresentsDocument() async throws {
        let fixture = MockedViewerWindowManager(files: [file, other], prefix: "ReopenPresentation.newTab")
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: file))
        await source.sidebar.awaitSettled()

        let tab = try #require(
            fixture.manager.openViewer(for: other, disposition: .newTab, relativeTo: source.window)
        )
        #expect(!tab.isPreviewingFolder, "生成直後にフォルダー提示になった")
        await tab.sidebar.awaitSettled()

        #expect(!tab.isPreviewingFolder)
        #expect(tab.presentationIntent.target == .file)
    }
}
