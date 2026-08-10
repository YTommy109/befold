import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// zoomChanged の JS → Swift デコードを検証する。
///
/// 倍率も per-file に永続化されるため、通知には「その倍率が属する文書」が載る。
/// ホスト側の現在 URL を使うと、切替直後に届いた古い通知が切替先の倍率を上書きして
/// 保存される(TASK-391 = スクロール位置 TASK-400 の同型 2 件目)。
/// 保存先の窓側の振る舞いは ViewerWindowZoomNotificationTests が担う。
@Suite
@MainActor
struct ViewerRendererZoomMessageTests {
    private typealias Stubs = ViewerRendererMessageStubs

    private func makeSUT() -> (renderer: ViewerRenderer, delegate: Stubs.Delegate) {
        let renderer = ViewerRenderer()
        let delegate = Stubs.Delegate()
        renderer.delegate = delegate
        return (renderer, delegate)
    }

    private func dispatch(_ renderer: ViewerRenderer, body: Any) {
        Stubs.dispatch(renderer, name: ViewerBridge.zoomChangedMessageName, body: body)
    }

    @Test("zoomChanged が onZoomChanged へ倍率と出所文書を渡す")
    func zoomChangedDispatchesZoomAndPath() {
        let (renderer, delegate) = makeSUT()
        var received: (zoom: Double, url: URL?)?
        delegate.onZoomChanged = { received = ($0, $1) }

        dispatch(renderer, body: ["zoom": NSNumber(value: 1.75), "path": "/tmp/dom-doc.md"])

        #expect(received?.zoom == 1.75)
        #expect(received?.url == URL(fileURLWithPath: "/tmp/dom-doc.md"))
    }

    @Test("zoomChanged の path が無ければ url は nil で配達される")
    func zoomChangedWithoutPathDeliversNilURL() {
        let (renderer, delegate) = makeSUT()
        var received: (url: URL?, called: Bool) = (nil, false)
        delegate.onZoomChanged = { _, url in received = (url, true) }

        dispatch(renderer, body: ["zoom": NSNumber(value: 1.75), "path": NSNull()])

        #expect(received.called)
        #expect(received.url == nil)
    }

    @Test("zoomChanged の zoom が数値でなければ onZoomChanged を呼ばない")
    func zoomChangedIgnoresNonNumberZoom() {
        let (renderer, delegate) = makeSUT()
        var called = false
        delegate.onZoomChanged = { _, _ in called = true }

        // 裸の値(オブジェクト化前の旧契約)は受け付けない
        dispatch(renderer, body: "1.5")
        dispatch(renderer, body: NSNumber(value: 1.5))
        // zoom が数値でないオブジェクト
        dispatch(renderer, body: ["zoom": "1.5", "path": "/tmp/a.md"])

        #expect(called == false)
    }
}
