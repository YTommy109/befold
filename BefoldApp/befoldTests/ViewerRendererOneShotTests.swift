import BefoldKit
@testable import BefoldRenderKit
import Testing
import WebKit

/// TASK-1.13: one-shot 合成 API の純粋な Outcome→描画変換(reject / truncation を含む)を、
/// WebView 構成を伴わずに検証する。ライブ経路(ViewerStore.apply / ViewerWebView)とは
/// 独立した QuickLook 想定の値変換ロジックを対象とする。
@Suite
struct ViewerRendererOneShotTests {
    private let chunkedReaderFactory: ViewerLoadPipeline.ChunkedReaderFactory = { cache, fileType in
        StringChunkReader(cache: cache, respectsCSVQuotes: fileType.csvDelimiter != nil)
    }

    // MARK: - Outcome → OneShotRender 変換

    @Test("full outcome の rejectReason がそのまま伝播する")
    func fullOutcomePropagatesRejectReason() {
        let outcome = ViewerLoadPipeline.Outcome.full(
            ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
            cache: nil
        )
        let render = ViewerRenderer.oneShotRender(
            from: outcome, url: URL(fileURLWithPath: "/tmp/big.md"), fileType: .markdown
        )

        #expect(render.rejectReason == .fileTooLarge)
        #expect(render.content.isEmpty)
        #expect(render.truncation == ViewerRenderer.TruncationState(isTruncated: false, lineCount: 0, failed: false))
    }

    @Test("full outcome の正常系は content を渡し reject しない")
    func fullOutcomePassesContentWhenAccepted() {
        let outcome = ViewerLoadPipeline.Outcome.full(
            ContentLoader.LoadedContent(rejectReason: nil, content: "# hello"),
            cache: nil
        )
        let render = ViewerRenderer.oneShotRender(
            from: outcome, url: URL(fileURLWithPath: "/tmp/a.md"), fileType: .markdown
        )

        #expect(render.rejectReason == nil)
        #expect(render.content == "# hello")
        #expect(render.truncation.isTruncated == false)
    }

    @Test("chunked outcome は先頭チャンクと切り詰め状態・表示行数を渡す")
    func chunkedOutcomeReportsTruncationAndLineCount() throws {
        let url = URL(fileURLWithPath: "/tmp/oneshot-chunk.log")
        let data = try #require("line1\nline2\nline3\n".data(using: .utf8))
        let cache = try NormalizedTextCache(data: data, normalizeFully: false, oneShotLoad: true)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: false)

        let outcome = ViewerLoadPipeline.Outcome.chunked(
            session: reader, cache: cache, firstChunk: "line1\nline2\n", isAtEnd: false
        )
        let render = ViewerRenderer.oneShotRender(
            from: outcome, url: url, fileType: .code(language: "plaintext")
        )

        #expect(render.rejectReason == nil)
        #expect(render.content == "line1\nline2\n")
        #expect(render.truncation.isTruncated == true)
        // 改行2個・末尾改行ありなので表示行数は 2。
        #expect(render.truncation.lineCount == 2)
    }

    @Test("chunked outcome で末尾が改行で終わらない場合は途中行も1行として数える(切り詰め時)")
    func chunkedOutcomeCountsTrailingPartialLine() throws {
        let url = URL(fileURLWithPath: "/tmp/oneshot-partial.log")
        let data = try #require("a\nb\nc".data(using: .utf8))
        let cache = try NormalizedTextCache(data: data, normalizeFully: false, oneShotLoad: true)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: false)

        // チャンク境界が行の途中に来る(強制分割)ケース。isAtEnd=false のときのみ
        // TruncationState は lineCount を保持する(非切り詰め時は 0 に正規化される)。
        let outcome = ViewerLoadPipeline.Outcome.chunked(
            session: reader, cache: cache, firstChunk: "a\nb\nc", isAtEnd: false
        )
        let render = ViewerRenderer.oneShotRender(
            from: outcome, url: url, fileType: .code(language: "plaintext")
        )

        #expect(render.truncation.isTruncated == true)
        // 改行2個 + 末尾の途中行 1 = 3 行。
        #expect(render.truncation.lineCount == 3)
    }

    @Test("missing outcome は unsupportedFormat へ安全側で倒す")
    func missingOutcomeRejectsAsUnsupported() {
        let render = ViewerRenderer.oneShotRender(
            from: .missing, url: URL(fileURLWithPath: "/tmp/gone.md"), fileType: .markdown
        )

        #expect(render.rejectReason == .unsupportedFormat)
        #expect(render.content.isEmpty)
    }

    // MARK: - displayedLineCount ヘルパ

    @Test("空文字列の表示行数は 0")
    func displayedLineCountForEmptyIsZero() {
        #expect(ViewerRenderer.displayedLineCount(of: "") == 0)
    }

    @Test("末尾改行なしの単一行は 1 行として数える")
    func displayedLineCountForSingleLineWithoutNewline() {
        #expect(ViewerRenderer.displayedLineCount(of: "single line") == 1)
    }

    // MARK: - loadOneShot 合成 API(ブリッジ無効構成)

    @Test("loadOneShot が oneShotLoad+ブリッジ無効で WebView を構成し reject を返す")
    @MainActor
    func loadOneShotBuildsWebViewAndReportsReject() async {
        let renderer = ViewerRenderer()
        renderer.rendererFeatures = RendererFeatures(
            allowDirectHTML: false, embedImages: false, allowsInteractiveBridging: false
        )

        let url = URL(fileURLWithPath: "/tmp/oneshot-api.md")
        let fileReader = InMemoryFileReader(files: [url.path: "# ok\n"])

        let result = await renderer.loadOneShot(
            url: url, fileReader: fileReader, chunkedReaderFactory: chunkedReaderFactory
        )

        #expect(result.rejectReason == nil)
        #expect(result.webView === renderer.webView)
        // ブリッジ無効構成では攻撃面となる2種のハンドラを登録しない。
        let names = ViewerRenderer.messageHandlerNames(for: renderer.rendererFeatures)
        #expect(!names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(!names.contains(ViewerBridge.referenceActivatedMessageName))
    }

    @Test("loadOneShot は非対応ファイルの rejectReason を返す")
    @MainActor
    func loadOneShotReportsRejectForBinary() async {
        let renderer = ViewerRenderer()
        renderer.rendererFeatures = RendererFeatures(
            allowDirectHTML: false, embedImages: false, allowsInteractiveBridging: false
        )

        let url = URL(fileURLWithPath: "/tmp/oneshot-binary.md")
        let fileReader = InMemoryFileReader(files: [url.path: "binary-ish"])
        // バイナリ判定された非対応ファイルは unsupportedFormat になる。
        fileReader.setBinary(true, at: url)

        let result = await renderer.loadOneShot(
            url: url, fileReader: fileReader, chunkedReaderFactory: chunkedReaderFactory
        )

        #expect(result.rejectReason == .unsupportedFormat)
    }
}
