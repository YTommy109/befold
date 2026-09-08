import BefoldKit
@testable import BefoldRenderKit
import Foundation
import Testing

/// **WKWebView 実体なしに描画コマンドの送出経路を検証する**(TASK-595.1)。
///
/// ここが `RenderSurface` 境界を入れた目的そのもの。従来この経路を組むには
/// `WKWebView` のサブクラス(`ViewerRendererMessageStubs.WebView`)が要り、
/// WebKit のプロセスが立ち上がっていた。fake の描画面なら、送られた JS 文字列と
/// その順序だけを純粋に見られる。
///
/// 送出の**順序**を見るのは、順序そのものが仕様だから。表示オプション
/// (行番号・モード・差分・切り詰め)を本文より後に送ると、本文の描画が
/// オプションを上書きして 1 サイクルぶん失われる(TASK-320 系の形)。
@Suite
struct RenderSurfaceDispatchTests {
    private static let filePath = URL(fileURLWithPath: "/tmp/task595.md")

    @MainActor
    private static func makeRenderer(_ surface: any RenderSurface) -> ViewerRenderer {
        let renderer = ViewerRenderer()
        renderer.surface = surface
        renderer.readiness.markReady()
        return renderer
    }

    private static func makeRequest(generation: Int) -> RenderRequest {
        RenderRequest(
            content: "# hello\n", contentRevision: 1, fileType: .markdown, filePath: filePath,
            isSourceMode: false, showLineNumbers: true,
            truncation: TruncationState(isTruncated: false, lineCount: 1, failed: false),
            generation: generation
        )
    }

    @Test("描画は表示オプションを本文より先に送る")
    @MainActor
    func displayOptionsPrecedeContent() async {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface)

        await renderer.scriptDispatcher.applyRender(
            surface: surface, request: Self.makeRequest(generation: 0),
            restoreFromPersistedPosition: false
        )

        // 本文(render)より前に行番号の指定が出ていること。番号ではなく相対順で見るのは、
        // 送る項目が増減しても意味が変わらないようにするため。
        let lineNumbersIndex = surface.evaluatedScripts.firstIndex { $0.contains("setLineNumbers") }
        let renderIndex = surface.evaluatedScripts.firstIndex { $0.hasPrefix("render(") }
        #expect(lineNumbersIndex != nil)
        #expect(renderIndex != nil)
        if let lineNumbersIndex, let renderIndex {
            #expect(lineNumbersIndex < renderIndex)
        }
    }

    @Test("世代を追い越された描画は 1 つも送らない")
    @MainActor
    func supersededRenderSendsNothing() async {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface)
        // 呼び出し後に別の updateContent が世代を進めた状況を模す。
        renderer.contentUpdateGeneration = 7

        await renderer.scriptDispatcher.applyRender(
            surface: surface, request: Self.makeRequest(generation: 3),
            restoreFromPersistedPosition: false
        )

        #expect(surface.evaluatedScripts.isEmpty)
    }

    @Test("直接 HTML モードへ入ると JS を止め、文書へ canvas を渡す")
    @MainActor
    func enteringDirectHTMLDisablesScriptAndHandsOverCanvas() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface)
        let htmlPath = URL(fileURLWithPath: "/tmp/task595.html")

        let entered = renderer.directHTML.enter(
            surface: surface, filePath: htmlPath,
            request: DirectHTMLLoadRequest(
                content: "<h1>hi</h1>", contentRevision: 1, fileType: .html,
                isSourceMode: false, hasDeclaredHTMLCharset: true
            )
        )

        #expect(entered)
        #expect(surface.isContentJavaScriptEnabled == false)
        #expect(surface.documentOwnsCanvasHistory == [true])
        #expect(surface.loads == [htmlPath])
    }
}
