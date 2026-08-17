import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// loadOneShot が実 WKWebView を構成し、viewer.html のロードと描画完了まで待つ経路を
/// 検証する。テスト対象自体を差し替えられず WebKit の実挙動が結果を左右するため
/// Integration に分離する(判定基準は docs/dev/coding_rule.md の
/// 「Unit / Integration の分離」節を参照)。値変換だけを見る単体側は
/// ViewerRendererOneShotTests にある。
@Suite(testTimeLimit())
struct ViewerRendererOneShotIntegrationTests {
    private let chunkedReaderFactory: ViewerLoadPipeline.ChunkedReaderFactory = { cache, fileType in
        try ViewerLoadPipeline.defaultChunkedReaderFactory(cache, fileType)
    }

    @Test("loadOneShot が oneShotLoad+ブリッジ無効で WebView を構成し reject を返す")
    @MainActor
    func loadOneShotBuildsWebViewAndReportsReject() async {
        let renderer = OneShotRenderer(features: .quickLookRestricted)

        let url = URL(fileURLWithPath: "/tmp/oneshot-api.md")
        let fileReader = InMemoryFileReader(files: [url.path: "# ok\n"])

        let result = await renderer.load(
            url: url, fileReader: fileReader, chunkedReaderFactory: chunkedReaderFactory
        )

        #expect(result.rejectReason == nil)
        #expect(result.webView === renderer.webView)
        // ブリッジ無効構成では攻撃面となる2種のハンドラを登録しない。
        let names = ViewerWebViewFactory.messageHandlerNames(for: RendererFeatures.quickLookRestricted)
        #expect(!names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(!names.contains(ViewerBridge.referenceActivatedMessageName))
    }

    /// QuickLook では allowDirectHTML=false のため HTML も viewer.html 内の iframe で描くが、
    /// 外部の HTML 文書であることは変わらないので canvas は文書に所有させる。透過のままだと
    /// 子文書の color-scheme 宣言が届かず、明るい背景前提の HTML が読めなくなる(TASK-511)。
    @Test("loadOneShot はHTML文書のときだけcanvasを文書へ明け渡す")
    @MainActor
    func loadOneShotHandsCanvasToHTMLDocumentsOnly() async {
        func drawsBackground(_ webView: WKWebView) -> Bool {
            (webView.value(forKey: "drawsBackground") as? Bool) ?? false
        }

        let htmlURL = URL(fileURLWithPath: "/tmp/task511-oneshot.html")
        let html = await OneShotRenderer(features: .quickLookRestricted).load(
            url: htmlURL,
            fileReader: InMemoryFileReader(files: [htmlURL.path: "<h1>ok</h1>\n"]),
            chunkedReaderFactory: chunkedReaderFactory
        )
        #expect(drawsBackground(html.webView))

        let mdURL = URL(fileURLWithPath: "/tmp/task511-oneshot.md")
        let markdown = await OneShotRenderer(features: .quickLookRestricted).load(
            url: mdURL,
            fileReader: InMemoryFileReader(files: [mdURL.path: "# ok\n"]),
            chunkedReaderFactory: chunkedReaderFactory
        )
        #expect(!drawsBackground(markdown.webView))
    }

    @Test("loadOneShot は非対応ファイルの rejectReason を返す")
    @MainActor
    func loadOneShotReportsRejectForBinary() async {
        let renderer = OneShotRenderer(features: .quickLookRestricted)

        let url = URL(fileURLWithPath: "/tmp/oneshot-binary.md")
        let fileReader = InMemoryFileReader(files: [url.path: "binary-ish"])
        // QuickLook でもバイナリ拒否の理由が汎用文言に丸められないこと(TASK-260)。
        fileReader.setBinary(true, at: url)

        let result = await renderer.load(
            url: url, fileReader: fileReader, chunkedReaderFactory: chunkedReaderFactory
        )

        #expect(result.rejectReason == .binaryContent)
    }

    /// loadOneShot が「描画を予約して即 return」ではなく、実際の描画完了まで待つこと。
    /// QuickLook はこの戻りの直後にプレビューを撮るため、待てていないと空白が表示される。
    /// 完了検知は callAsyncJavaScript が受け取る render() の Promise 解決に依存するので、
    /// 戻った時点で DOM に描画結果が入っていることを実際の WebView から読んで確かめる。
    @Test("loadOneShot は描画完了まで待ってから返る")
    @MainActor
    func loadOneShotAwaitsRenderCompletion() async throws {
        let renderer = OneShotRenderer(features: .quickLookRestricted)
        // 既定の 3 秒は QuickLook 向けの上限で、全テスト並走時の WebView ロードには
        // 足りずタイムアウト側が先に発火しうる。ここでは打ち切りではなく
        // 「完了まで待つ」ことを見たいので十分に長く取る。
        renderer.renderTimeout = .seconds(60)

        let url = URL(fileURLWithPath: "/tmp/oneshot-await.md")
        let fileReader = InMemoryFileReader(files: [url.path: "# heading-marker\n"])

        let result = await renderer.load(
            url: url, fileReader: fileReader, chunkedReaderFactory: chunkedReaderFactory
        )

        let html = try await result.webView.evaluateJavaScript(
            "document.getElementById('diagram-wrap').innerHTML"
        ) as? String
        #expect(html?.contains("heading-marker") == true)
    }
}
