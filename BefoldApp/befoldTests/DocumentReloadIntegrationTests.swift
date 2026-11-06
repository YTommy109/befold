import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// 実際の delegate 配送と描画済み DOM を検証する。Swift からの直接呼び出しだけでは
/// optional な Objective-C selector の登録漏れを検知できない。
@Suite(testTimeLimit())
@MainActor
struct DocumentReloadIntegrationTests {
    final class Delegate: ViewerRendererDelegate {
        var reloadCount = 0
        func rendererDidRequestReload(_ renderer: ViewerRenderer) {
            reloadCount += 1
            Self.render(renderer, revision: reloadCount + 1)
        }

        static func render(_ renderer: ViewerRenderer, revision: Int) {
            renderer.updateContent(
                "# Reload sentinel", contentRevision: revision, fileType: .markdown,
                filePath: URL(fileURLWithPath: "/tmp/reload-sentinel.md"),
                hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
                truncation: .init(isTruncated: false, lineCount: 0, failed: false)
            )
        }
    }

    @Test("実 WebKit の再読み込み後にも Markdown 本文が残る")
    func realReloadKeepsMarkdown() async throws {
        let renderer = ViewerRenderer()
        let webView = ViewerRendererMessageStubs.makeWebView(with: renderer)
        webView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let delegate = Delegate()
        renderer.delegate = delegate
        // WebKit の完了にはメインランループを進める yield が必要。時間上限で失敗を確定する。
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !renderer.readiness.isReady, ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(renderer.readiness.isReady)
        Delegate.render(renderer, revision: 1)
        while renderer.rendered.contentRevision != 1, ContinuousClock.now < deadline {
            await Task.yield()
        }
        var before = ""
        while !before.contains("Reload sentinel"), ContinuousClock.now < deadline {
            before = try await webView.evaluateJavaScript("document.body.innerText") as? String ?? ""
            await Task.yield()
        }
        try #require(before.contains("Reload sentinel"))
        webView.reload()
        while delegate.reloadCount == 0, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(delegate.reloadCount == 1)
        while renderer.rendered.contentRevision != 2, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let after = try await webView.evaluateJavaScript("document.body.innerText") as? String
        #expect(after?.contains("Reload sentinel") == true)
    }
}
