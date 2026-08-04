import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// 見えていない間は再描画しないこと(ADR 0002 段 5 / TASK-272)を検証する。
/// 抑止中もミラーは更新しないため、見える状態へ戻った時点で最新の内容が 1 度だけ描画される。
@Suite(testTimeLimit())
@MainActor
struct ViewerRendererVisibilityTests {
    private static let truncation = ViewerRenderer.TruncationState(isTruncated: false, lineCount: 0, failed: false)
    private let file = URL(fileURLWithPath: "/tmp/visibility.md")

    private func makeRenderer() -> ViewerRenderer {
        let renderer = ViewerRenderer()
        renderer.webView = WKWebView()
        renderer.isReady = true
        return renderer
    }

    private func update(_ renderer: ViewerRenderer, content: String, revision: Int) {
        renderer.updateContent(
            content, contentRevision: revision, fileType: .markdown, filePath: file,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
    }

    @Test("見えていない間の更新は描画されず、描画済みミラーも進めない")
    func suppressesRenderWhileHidden() async {
        let renderer = makeRenderer()
        renderer.isVisible = false

        update(renderer, content: "# 更新 1", revision: 1)
        update(renderer, content: "# 更新 2", revision: 2)
        await Task.yield()

        #expect(renderer.rendered.contentRevision == nil)
        #expect(renderer.rendered.filePath == nil)
    }

    @Test("見える状態へ戻ると、抑止していた更新が最新の内容 1 回で反映される")
    func rendersLatestContentOnceWhenVisibleAgain() async {
        let renderer = makeRenderer()
        renderer.isVisible = false
        update(renderer, content: "# 更新 1", revision: 1)
        update(renderer, content: "# 更新 2", revision: 2)

        // ホスト(ViewerWebView)は可視状態が変わると最新の値で呼び直す。
        renderer.isVisible = true
        update(renderer, content: "# 更新 2", revision: 2)
        await waitUntilYielding { renderer.rendered.contentRevision == 2 }

        #expect(renderer.rendered.contentRevision == 2)
        #expect(renderer.rendered.filePath == file)
    }

    @Test("既定では可視として扱う(QuickLook など可視性を渡さない利用者を壊さない)")
    func defaultsToVisible() async {
        let renderer = makeRenderer()
        #expect(renderer.isVisible)

        update(renderer, content: "# 内容", revision: 1)
        await waitUntilYielding { renderer.rendered.contentRevision == 1 }
        #expect(renderer.rendered.contentRevision == 1)
    }
}
