import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 戻る/進む履歴の積み方と、それに連動する「戻る」「進む」メニューの有効判定を検証する
/// unit テスト。履歴を積む経路は switchFile とリンク遷移(handleOpenReference)の 2 つあり、
/// どちらからでも同じ履歴として往復できることをここで押さえる。
/// InMemoryFileReader でモック化して実 FS を踏まない。
@Suite("ViewerWindowController の戻る/進む履歴")
@MainActor
struct ViewerWindowControllerHistoryTests {
    @Test("switchFile で履歴が積まれ戻ると元ファイルに復帰する")
    func switchFilePushesHistoryAndBackRestores() {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeMockedViewerWindowController(
            primary: fileA, others: [fileB], defaults: makeIsolatedDefaults(prefix: "History")
        )
        defer { controller.close() }

        controller.switchFile(to: fileB)
        #expect(controller.fileURL.lastPathComponent == "b.mmd")
        #expect(controller.canGoBack == true)

        controller.navigateHistory(by: -1)
        #expect(controller.fileURL.lastPathComponent == "a.mmd")
        #expect(controller.canGoForward == true)
        #expect(controller.canGoBack == false)
    }

    @Test("戻る操作自体は新しい履歴を積まない")
    func navigatingHistoryDoesNotRecord() {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeMockedViewerWindowController(
            primary: fileA, others: [fileB], defaults: makeIsolatedDefaults(prefix: "History")
        )
        defer { controller.close() }
        controller.switchFile(to: fileB)

        controller.navigateHistory(by: -1) // a へ戻る
        controller.navigateHistory(by: 1) // b へ進む

        // 破棄されずに往復できる = 戻る/進むで push されていない
        #expect(controller.fileURL.lastPathComponent == "b.mmd")
        #expect(controller.canGoForward == false)
        #expect(controller.canGoBack == true)
    }

    @Test("戻る/進むメニューは対応する履歴があるときだけ有効")
    func goBackAndForwardMenuValidation() {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeMockedViewerWindowController(primary: fileA, others: [fileB])
        defer { controller.close() }
        let backItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.goBack(_:)), keyEquivalent: ""
        )
        let forwardItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.goForward(_:)), keyEquivalent: ""
        )

        #expect(controller.validateMenuItem(backItem) == false)
        #expect(controller.validateMenuItem(forwardItem) == false)

        controller.switchFile(to: fileB)
        #expect(controller.validateMenuItem(backItem) == true)
        #expect(controller.validateMenuItem(forwardItem) == false)

        controller.navigateHistory(by: -1)
        #expect(controller.validateMenuItem(backItem) == false)
        #expect(controller.validateMenuItem(forwardItem) == true)
    }

    @Test("リンク遷移で履歴が積まれ、戻る操作で復帰する")
    func handleOpenReferenceRecordsHistoryAndBackRestores() async {
        let fileA = URL(fileURLWithPath: "/mock/a.md")
        let fileB = URL(fileURLWithPath: "/mock/b.md")
        let controller = makeMockedViewerWindowController(
            primary: fileA, others: [fileB], contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "OpenReference")
        )
        defer { controller.close() }

        controller.handleOpenReference(href: "b.md", disposition: .currentTab)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(controller.fileURL.lastPathComponent == "b.md")
        #expect(controller.canGoBack == true)

        controller.navigateHistory(by: -1)

        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(controller.canGoForward == true)
    }
}
