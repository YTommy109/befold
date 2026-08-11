import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// applyAppend の「切り詰めバナーの送信とミラー確定を同一の同期区間に置く」規則を守らせる。
/// 発行点は TASK-440 で ViewerScriptDispatcher へ移したため、そちら経由で呼ぶ。
/// 送信を世代ガードより前へ戻すと、追い越された呼び出しが「JS へは送ったのにミラーは
/// 旧値のまま」を残し、次の更新でバナーの再送がスキップされて実 DOM と食い違う
/// (TASK-320 → 334 → 336 と同系列の確定漏れ / TASK-417)。
@Suite(testTimeLimit())
struct ViewerRendererAppendTruncationTests {
    private static let renderedTruncation = TruncationState(
        isTruncated: true, lineCount: 100, failed: false
    )
    private static let incomingTruncation = TruncationState(
        isTruncated: true, lineCount: 200, failed: false
    )

    /// 直近描画の状態。各ケースはここを起点に applyAppend を直接呼ぶ。
    @MainActor
    private static func makeRenderer(_ webView: WKWebView) -> ViewerRenderer {
        let renderer = ViewerRenderer()
        renderer.webView = webView
        renderer.readiness.markReady()
        // ミラーの確定入口は recordRendered 1 つだけ(TASK-320 / 334 / 440)。
        renderer.recordRendered(RenderedStateMirror(
            contentRevision: 5, fileType: .markdown, filePath: URL(fileURLWithPath: "/tmp/task417.md"),
            showLineNumbers: false, isSourceMode: false,
            truncation: renderedTruncation, diffState: DiffState.none
        ))
        return renderer
    }

    private static func makeRequest(generation: Int) -> AppendRequest {
        AppendRequest(
            chunk: "next chunk\n", contentRevision: 6, fileType: .markdown,
            filePath: URL(fileURLWithPath: "/tmp/task417.md"), isSourceMode: false,
            truncation: incomingTruncation, generation: generation
        )
    }

    @Test("世代を追い越された追記は JS へ何も送らない")
    @MainActor
    func supersededAppendSendsNothing() async {
        let webView = ViewerRendererMessageStubs.WebView()
        let renderer = Self.makeRenderer(webView)
        // 呼び出し後に別の updateContent が世代を進めた状況を模す。
        renderer.contentUpdateGeneration = 9

        await renderer.scriptDispatcher.applyAppend(webView: webView, request: Self.makeRequest(generation: 8))

        // 1 つでも送っていれば、ミラーが旧値のまま JS だけ進んだ状態を作ってしまう。
        #expect(webView.evaluatedScripts.isEmpty)
        #expect(renderer.rendered.truncation == Self.renderedTruncation)
    }

    @Test("世代が一致する追記は切り詰めバナーを送り、同じ呼び出しでミラーへ確定する")
    @MainActor
    func currentAppendSendsTruncationAndRecordsIt() async {
        let webView = ViewerRendererMessageStubs.WebView()
        let renderer = Self.makeRenderer(webView)
        renderer.contentUpdateGeneration = 9

        await renderer.scriptDispatcher.applyAppend(webView: webView, request: Self.makeRequest(generation: 9))

        #expect(webView.evaluatedScripts.contains(Self.incomingTruncation.script))
        #expect(renderer.rendered.truncation == Self.incomingTruncation)
        #expect(renderer.rendered.contentRevision == 6)
    }
}
