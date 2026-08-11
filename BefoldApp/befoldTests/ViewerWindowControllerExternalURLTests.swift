import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 本文中の外部 URL(http/https)を開く経路だけを検証する。
///
/// 検証の軸は 2 つ。届け先が注入された externalOpener であること(テスト中に実ブラウザを
/// 起動しないことの担保でもある)と、解決を待つ間にウィンドウが閉じられたら他の分岐と
/// 同じく抑止されること。
@Suite
@MainActor
struct ViewerWindowControllerExternalURLTests {
    /// 外部 URL の届け先を記録するコントローラーを作る。
    private func makeController(
        opened: LockedBox<[URL]>, prefix: String
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: URL(fileURLWithPath: "/mock/a.md"),
            contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: prefix),
            externalOpener: { url in opened.set(opened.get() + [url]) }
        ).controller
    }

    @Test("外部 URL のリンク遷移は externalOpener を通す")
    func handleOpenReferenceRoutesExternalURLThroughOpener() async {
        let opened = LockedBox<[URL]>([])
        let controller = makeController(opened: opened, prefix: "OpenExternal")
        defer { controller.close() }

        controller.handleOpenReference(href: "https://example.com", disposition: .currentTab)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(opened.get().map(\.absoluteString) == ["https://example.com"])
    }

    /// 解決(git subprocess を伴いうる)を待つ間にウィンドウが閉じられたら、外部 URL も
    /// 他の分岐と同じく抑止されなければならない。NSWorkspace を直に呼んでいた頃は、
    /// 閉じたはずのウィンドウの cmd+click が後からブラウザを前面に出していた(TASK-449)。
    @Test("ウィンドウ解放後は、外部 URL の届け先も呼ばれない")
    func referenceActionsStopOpeningExternalURLAfterWindowIsReleased() throws {
        let externalURL = try #require(URL(string: "https://example.com"))
        let opened = LockedBox<[URL]>([])
        var actions: ReferenceActions?
        weak var releasedController: ViewerWindowController?
        // autoreleasepool で囲まないと、ウィンドウを閉じてもこのスコープを抜けた時点では
        // まだ解放されず、前提(解放済み)が成り立たない。
        autoreleasepool {
            let controller = makeController(opened: opened, prefix: "OpenExternalReleased")
            actions = controller.referenceActions
            releasedController = controller
            controller.close()
        }
        #expect(releasedController == nil, "controller が解放されておらず、前提が成り立っていない")

        actions?.openExternal(externalURL)

        #expect(opened.get().isEmpty)
    }
}
