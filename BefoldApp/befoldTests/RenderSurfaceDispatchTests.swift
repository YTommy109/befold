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

/// 描画面が未設定でも readiness ゲートが開くことの担保（TASK-600）。
///
/// TASK-595.2 で `didFinish` を `surfaceDidFinishLoad` へ移した際、旧実装が
/// デリゲート引数で受けていた WebView を `renderer.surface` の読み出しへ替え、
/// それを guard へ併合してしまった。surface を要るのは倍率の当て直しだけなのに、
/// nil だと `markReady()` まで飛ばされ、`runWhenReady` に積まれた描画要求が
/// 全部落ちて窓が白いままになる。
@Suite
struct SurfaceReadinessGateTests {
    @Test("描画面が未設定でも、ロード完了で保留中の描画が走る")
    @MainActor
    func readinessOpensWithoutSurface() {
        let renderer = ViewerRenderer()
        // surface は入れない（`WebKitRenderSurface.make(for:…)` の adopt より前に
        // didFinish が届いた状況）。
        #expect(renderer.surface == nil)

        var didRender = false
        renderer.runWhenReady { didRender = true }
        #expect(didRender == false, "ready 前に走っては前提が成り立たない")

        renderer.navigationCoordinator.surfaceDidFinishLoad()

        #expect(didRender, "surface が nil でも readiness ゲートは開かなければならない")
    }
}

/// 面の実装型に依らず遮断ポリシーと後始末が行われることの担保（TASK-599）。
///
/// TASK-595 では `as? WebKitRenderSurface` で分岐しており、WebKit 以外の面が入ると
/// リモート読み込みの遮断も postMessage ハンドラの解除も**黙って飛んだ**。
/// 操作を `RenderSurface` へ出して呼び出しを無条件にしたので、fake でも
/// 呼ばれることを観測できる。ここが 0 回になったら、分岐が復活したということ。
@Suite
struct SurfacePolicyApplicationTests {
    @Test("viewer.html のロードは、面の実装型に依らず遮断ポリシーを適用してから行う")
    @MainActor
    func viewerHTMLLoadAppliesRemoteLoadPolicy() {
        let surface = ViewerRendererMessageStubs.Surface()
        #expect(surface.remoteLoadPolicyApplications == 0)

        ViewerWebViewFactory.loadViewerHTML(into: surface)

        #expect(
            surface.remoteLoadPolicyApplications == 1,
            "遮断ポリシーの適用が飛ばされている（実装型で分岐していないか）"
        )
        // 適用してから読み込む順序も見る。適用前に読むと、その 1 回が守られない。
        #expect(surface.loads.count == 1)
    }

    @Test("後始末は、面の実装型に依らず登録したハンドラ名を外す")
    @MainActor
    func dismantleRemovesHandlersRegardlessOfImplementation() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = ViewerRenderer()
        renderer.surface = surface

        renderer.dismantle()

        let expected = ViewerWebViewFactory.messageHandlerNames(for: renderer.rendererFeatures)
        #expect(!expected.isEmpty, "前提: 登録するハンドラが 1 つ以上ある")
        #expect(surface.removedMessageHandlerNames == expected)
    }
}
