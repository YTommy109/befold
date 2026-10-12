import AppKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// `drawsBackground` の KVC(非公開キー)が OS 更新後も実際に地を塗る/塗らないへ効いているかを
/// 実ピクセルで見る(TASK-695)。公開 API の `underPageBackgroundColor` は透過を作れないため
/// KVC を撤去できない。キーが消えれば `setValue` が例外で落ち、意味が変われば本テストが落ちる。
@Suite(testTimeLimit())
struct ViewerCanvasPixelTests {
    @Test("drawsBackground の KVC が実 WebView の地の透過/不透過へ効く")
    @MainActor
    func documentOwnsCanvasTogglesPixelAlpha() async throws {
        let transparent = try await cornerAlpha(documentOwns: false)
        let opaque = try await cornerAlpha(documentOwns: true)
        #expect(transparent == 0)
        #expect(opaque == 1)
    }

    @MainActor
    private func cornerAlpha(documentOwns: Bool) async throws -> CGFloat {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        ViewerWebViewFactory.setDocumentOwnsCanvas(documentOwns, on: webView)
        let loader = LoadWaiter()
        webView.navigationDelegate = loader
        await loader.load("<html><body></body></html>", in: webView)
        let image = try await webView.takeSnapshot(configuration: WKSnapshotConfiguration())
        let tiff = try #require(image.tiffRepresentation)
        let color = try #require(NSBitmapImageRep(data: tiff)?.colorAt(x: 10, y: 10))
        return color.alphaComponent
    }
}

/// `didFinish` を待つ。固定 sleep だと CI の遅い環境で描画前に撮ってしまう。
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func load(_ html: String, in webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
}
