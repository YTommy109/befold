import AppKit
@testable import befold
import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing
import WebKit

/// WebViewCommandController の GUI 非依存部分(webView 未接続時のno-op安全性・
/// isDirectHTMLMode の委譲)を検証する。WKWebView 実体を要する経路は手動チェック対象。
@Suite
@MainActor
struct WebViewCommandControllerTests {
    private func makeController(
        proxy: WebViewProxy = WebViewProxy(),
        url: URL = URL(fileURLWithPath: "/tmp/a.md"),
        isPreviewingFolder: @escaping () -> Bool = { false }
    ) -> WebViewCommandController {
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        return WebViewCommandController(
            webViewProxy: proxy,
            perFileState: PerFileStateStore(defaults: defaults),
            currentURL: { url },
            isPreviewingFolder: isPreviewingFolder
        )
    }

    @Test("フォルダー一覧の表示中は、生きている WebView があっても文書操作を許さない")
    func blocksDocumentCommandsWhilePreviewingFolder() {
        let proxy = WebViewProxy()
        proxy.webView = WKWebView()
        var isPreviewingFolder = false
        let controller = makeController(proxy: proxy, isPreviewingFolder: { isPreviewingFolder })

        #expect(controller.canOperateOnVisibleDocument)

        isPreviewingFolder = true
        #expect(!controller.canOperateOnVisibleDocument)

        // フォルダー表示中はコマンドを呼んでも何も起きない(クラッシュもしない)
        controller.zoomIn()
        controller.openFind()
        controller.printDocument(over: nil)
    }

    @Test("WebView が無ければフォルダー表示でなくても文書操作は不可")
    func requiresLiveWebView() {
        #expect(!makeController().canOperateOnVisibleDocument)
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
