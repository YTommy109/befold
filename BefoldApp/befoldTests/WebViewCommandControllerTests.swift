import AppKit
@testable import befold
import BefoldRenderKit
import Foundation
import Testing

/// WebViewCommandController の GUI 非依存部分(webView 未接続時のno-op安全性・
/// isDirectHTMLMode の委譲)を検証する。WKWebView 実体を要する経路は手動チェック対象。
@Suite
@MainActor
struct WebViewCommandControllerTests {
    private func makeController(
        proxy: WebViewProxy = WebViewProxy(),
        url: URL = URL(fileURLWithPath: "/tmp/a.md")
    ) -> WebViewCommandController {
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        return WebViewCommandController(
            webViewProxy: proxy,
            perFileState: PerFileStateStore(defaults: defaults),
            currentURL: { url }
        )
    }

    @Test("isDirectHTMLMode は webViewProxy の値をそのまま反映する")
    func isDirectHTMLModeReflectsProxy() {
        let proxy = WebViewProxy()
        let controller = makeController(proxy: proxy)
        #expect(!controller.isDirectHTMLMode)

        proxy.isDirectHTMLMode = true
        #expect(controller.isDirectHTMLMode)
    }

    @Test("webView 未接続でも各コマンドはクラッシュせず no-op となる")
    func commandsAreNoOpWithoutWebView() {
        let controller = makeController()

        controller.zoomIn()
        controller.zoomOut()
        controller.resetZoom()
        controller.applyStoredZoom()
        controller.openFind()
        controller.findNext()
        controller.findPrevious()
        controller.printDocument(over: nil)
        controller.saveCurrentScrollPosition(for: URL(fileURLWithPath: "/tmp/a.md"), mode: .rendered)
    }
}
