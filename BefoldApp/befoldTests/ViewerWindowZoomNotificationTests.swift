@testable import befold
import BefoldKit
import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// 倍率の保存キーは「その倍率が属する文書」から決める(TASK-391)。
///
/// スクロール位置(TASK-400)と同型のレース。ズーム操作の直後にファイルを切り替えると、
/// 切替前の文書の zoomChanged が遅れて届く。受け取り側が現在表示中の fileURL を
/// キーにすると、切替先の保存倍率を旧文書の倍率で上書きし、さらに切替先のライブ倍率
/// (store.zoom)まで書き換えてしまう。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowZoomNotificationTests {
    private let origin = URL(fileURLWithPath: "/mock/origin.md")
    private let destination = URL(fileURLWithPath: "/mock/destination.md")

    private func makeFixture() -> ViewerWindowControllerFixture {
        ViewerWindowControllerFixture(
            file: origin, extraFiles: [destination],
            prefix: "ViewerWindowZoomNotification"
        )
    }

    @Test("切替後に届いた切替前ファイルの通知は、切替先のキーへ保存されない")
    func lateNotificationDoesNotWriteToDestinationKey() {
        let fixture = makeFixture()
        let controller = fixture.controller
        fixture.zoomStore.setZoom(1.5, for: destination)
        controller.switchFile(to: destination)
        #expect(controller.fileURL == destination)

        // 切替前ファイル(origin)の DOM から遅れて届いた通知。
        controller.renderer(ViewerRenderer(), didChangeZoom: 2.0, for: origin)

        #expect(fixture.zoomStore.zoom(for: destination) == 1.5)
        #expect(fixture.zoomStore.zoom(for: origin) == 2.0)
    }

    /// ライブ値は「いまこの窓が出している文書」の倍率。出所が現在の文書と違う
    /// 遅延通知で書き換えると、画面の倍率が切替前の値へ飛ぶ。
    @Test("切替後に届いた切替前ファイルの通知は、ライブ倍率を上書きしない")
    func lateNotificationDoesNotOverwriteLiveZoom() {
        let fixture = makeFixture()
        let controller = fixture.controller
        fixture.zoomStore.setZoom(1.5, for: destination)
        controller.switchFile(to: destination)
        #expect(controller.store.zoom == 1.5)

        controller.renderer(ViewerRenderer(), didChangeZoom: 2.0, for: origin)

        #expect(controller.store.zoom == 1.5)
    }

    @Test("出所が現在の文書と一致する通知は、ライブ倍率と保存値の両方を更新する")
    func matchingNotificationUpdatesLiveAndStoredZoom() {
        let fixture = makeFixture()
        let controller = fixture.controller

        controller.renderer(ViewerRenderer(), didChangeZoom: 1.75, for: origin)

        #expect(controller.store.zoom == 1.75)
        #expect(fixture.zoomStore.zoom(for: origin) == 1.75)
    }

    @Test("出所の文書が定まらない(url が nil)通知は保存もライブ更新もしない")
    func notificationWithoutURLIsIgnored() {
        let fixture = makeFixture()
        let controller = fixture.controller
        let liveZoomBefore = controller.store.zoom

        controller.renderer(ViewerRenderer(), didChangeZoom: 2.0, for: nil)

        #expect(controller.store.zoom == liveZoomBefore)
        #expect(fixture.zoomStore.zoom(for: origin) == ZoomStore.defaultZoom)
    }
}
