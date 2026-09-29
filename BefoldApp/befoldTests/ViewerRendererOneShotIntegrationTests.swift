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

    /// 拒否の経路でも面の構成は通る（`OneShotRenderer.load` は描画の前に canvas の所有を
    /// 決める）ので、canvas の配線もここで見る。判定そのもの（HTML 文書だけが所有する）は
    /// `ViewerCanvasOwnershipTests.documentOwnsCanvasOnlyForHTMLDocuments` が純関数で持つ。
    /// 描画完了を待たずに済むため、実 WebView のロードを 1 回ぶん減らせる(TASK-662.2)。
    ///
    /// QuickLook では allowDirectHTML=false のため HTML も viewer.html 内の iframe で描くが、
    /// 外部の HTML 文書であることは変わらないので canvas は文書に所有させる。透過のままだと
    /// 子文書の color-scheme 宣言が届かず、明るい背景前提の HTML が読めなくなる(TASK-511)。
    @Test("loadOneShot は非対応ファイルの rejectReason を返し、HTML 文書なら canvas を明け渡す")
    @MainActor
    func loadOneShotReportsRejectForBinary() async {
        let renderer = OneShotRenderer(features: .quickLookRestricted)

        let url = URL(fileURLWithPath: "/tmp/oneshot-binary.html")
        let fileReader = InMemoryFileReader(files: [url.path: "binary-ish"])
        // QuickLook でもバイナリ拒否の理由が汎用文言に丸められないこと(TASK-260)。
        fileReader.setBinary(true, at: url)

        let result = await renderer.load(
            url: url, fileReader: fileReader, chunkedReaderFactory: chunkedReaderFactory
        )

        #expect(result.rejectReason == .binaryContent)
        #expect((result.webView.value(forKey: "drawsBackground") as? Bool) == true)
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

        #expect(result.rejectReason == nil)
        // 内包するレンダラが描画完了まで面を保持し続けている。
        #expect(result.webView === renderer.webView)
        let html = try await result.webView.evaluateJavaScript(
            "document.getElementById('diagram-wrap').innerHTML"
        ) as? String
        #expect(html?.contains("heading-marker") == true)
    }
}
