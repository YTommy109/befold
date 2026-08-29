@testable import befold
import BefoldKit
import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// スクロール位置の記録キーは「その位置が属する文書」から決める(TASK-400)。
///
/// JS 側の通知は 200ms デバウンスされるため、ファイル切替の直後に切替前の文書の通知が
/// 届きうる。受け取り側が現在表示中の fileURL をキーにすると、切替前の位置が切替先の
/// キーへ記録され、切替先の文書が他文書の位置で開く。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowScrollPositionNotificationTests {
    private let origin = URL(fileURLWithPath: "/mock/origin.md")
    private let destination = URL(fileURLWithPath: "/mock/destination.md")

    private func makeFixture() -> ViewerWindowControllerFixture {
        ViewerWindowControllerFixture(
            file: origin, extraFiles: [destination],
            prefix: "ViewerWindowScrollPositionNotification"
        )
    }

    @Test("切替後に届いた切替前ファイルの通知は、切替先のキーへ記録されない")
    func lateNotificationDoesNotWriteToDestinationKey() {
        let fixture = makeFixture()
        let controller = fixture.controller
        controller.switchFile(to: destination)
        #expect(controller.fileURL == destination)
        let mode = ViewerBridge.ViewMode(isSourceMode: controller.store.isSourceMode)

        // 切替前ファイル(origin)の DOM から遅れて届いた通知。
        controller.renderer(ViewerRenderer(), didChangeScrollPosition: 480, for: origin, mode: mode)

        let memory = controller.documentPresenter.presentationMemory
        #expect(memory.scrollPosition(for: destination, mode: mode) == 0)
        #expect(memory.scrollPosition(for: origin, mode: mode) == 480)
    }

    @Test("出所の文書が定まらない(url が nil)通知は記録しない")
    func notificationWithoutURLIsIgnored() {
        let fixture = makeFixture()
        let controller = fixture.controller
        let mode = ViewerBridge.ViewMode(isSourceMode: controller.store.isSourceMode)

        controller.renderer(ViewerRenderer(), didChangeScrollPosition: 120, for: nil, mode: mode)

        #expect(controller.documentPresenter.presentationMemory.scrollPosition(for: origin, mode: mode) == 0)
    }
}
