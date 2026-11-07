import AppKit
import BefoldKit
@testable import BefoldRenderKit
import Testing

/// WebKit の再読み込みを文書の読み込み元へ戻し、viewer.html 自体には遷移しない。
@Suite
@MainActor
struct DocumentReloadTests {
    final class Delegate: ViewerRendererDelegate {
        private(set) var reloadCount = 0

        func rendererDidRequestReload(_: ViewerRenderer) {
            reloadCount += 1
        }
    }

    @Test("通常表示と直接 HTML 表示の再読み込みはホストへ届く", arguments: [false, true])
    func reloadRequestsDocument(directHTML: Bool) {
        let renderer = ViewerRenderer()
        let surface = ViewerRendererMessageStubs.Surface()
        renderer.surface = surface
        renderer.directHTML.simulateForTesting(active: directHTML)
        let delegate = Delegate()
        renderer.delegate = delegate
        var decisions: [SurfaceNavigationDecision] = []
        #expect(renderer.surfaceEventBridge.responds(to: NSSelectorFromString(
            "webView:decidePolicyForNavigationAction:decisionHandler:"
        )))

        renderer.surfaceEventBridge.webView(
            SurfaceNavigationStubs.placeholderWebView,
            decidePolicyFor: SurfaceNavigationStubs.NavigationAction(
                type: .reload, url: URL(fileURLWithPath: "/tmp/viewer.html")
            ),
            decisionHandler: { decisions.append($0 == .allow ? .allow : .cancel) }
        )

        #expect(decisions == [.cancel])
        #expect(delegate.reloadCount == 1)
        #expect(surface.loads.isEmpty)
    }
}
