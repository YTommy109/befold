import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// canvas(地)の所有者の判定と適用を検証する。
///
/// 既定では地の色は `ViewerTheme.canvas` が唯一の定義で WKWebView は透過だが、外部の
/// HTML 文書だけは例外でブラウザと同じく文書が canvas ごと所有する。透過のままだと、
/// 明るい背景を前提に文字色だけを指定した HTML がダークキャンバス上に載って読めなくなる
/// (TASK-511)。この対は enter / exit とセットで倒す必要があり、破れても
/// `RenderedStateMirror` の比較には現れないためここで直接押さえる。
@Suite(testTimeLimit())
struct ViewerCanvasOwnershipTests {
    private static func drawsBackground(_ webView: WKWebView) -> Bool {
        (webView.value(forKey: "drawsBackground") as? Bool) ?? false
    }

    @Test("外部のHTML文書だけがcanvasを所有する")
    func documentOwnsCanvasOnlyForHTMLDocuments() {
        #expect(ViewerWebViewFactory.documentOwnsCanvas(fileType: .html, isSourceMode: false))
        // ソース表示の HTML は befold がコードとして描くので該当しない。
        #expect(!ViewerWebViewFactory.documentOwnsCanvas(fileType: .html, isSourceMode: true))
        #expect(!ViewerWebViewFactory.documentOwnsCanvas(fileType: .markdown, isSourceMode: false))
        #expect(!ViewerWebViewFactory.documentOwnsCanvas(fileType: .mmd, isSourceMode: false))
    }

    @Test("直接HTMLモードへ入るとcanvasを文書へ明け渡す")
    @MainActor
    func enterHandsCanvasToDocument() {
        let renderer = ViewerRenderer()
        let webView = WKWebView()
        renderer.webView = webView
        ViewerWebViewFactory.setDocumentOwnsCanvas(false, on: webView)

        let url = URL(fileURLWithPath: "/tmp/task511-enter.html")
        _ = renderer.directHTML.enter(
            webView: webView,
            filePath: url,
            request: DirectHTMLLoadRequest(
                content: "<h1>x</h1>", contentRevision: 1, fileType: .html,
                isSourceMode: false, hasDeclaredHTMLCharset: true
            )
        )

        #expect(Self.drawsBackground(webView))
    }

    @Test("直接HTMLモードから復帰するとcanvasは透過へ戻る")
    @MainActor
    func exitRestoresTransparentCanvas() {
        let renderer = ViewerRenderer()
        let webView = WKWebView()
        renderer.webView = webView
        ViewerWebViewFactory.setDocumentOwnsCanvas(true, on: webView)

        renderer.directHTML.exit(webView: webView) {}

        #expect(!Self.drawsBackground(webView))
    }
}
