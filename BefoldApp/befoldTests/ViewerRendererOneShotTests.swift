import BefoldKit
@testable import BefoldRenderKit
import Testing
import WebKit

/// one-shot 合成 API の純粋な Outcome→描画変換(reject / truncation を含む)を、
/// WebView 構成を伴わずに検証する。実 WKWebView を構成する loadOneShot 自体の経路は
/// ViewerRendererOneShotIntegrationTests へ分離した。ライブ経路(ViewerStore.apply / ViewerWebView)とは
/// 独立した QuickLook 想定の値変換ロジックを対象とする。
@Suite
struct ViewerRendererOneShotTests {
    private let chunkedReaderFactory: ViewerLoadPipeline.ChunkedReaderFactory = { cache, fileType in
        try ViewerLoadPipeline.defaultChunkedReaderFactory(cache, fileType)
    }

    // MARK: - Outcome → OneShotRender 変換

    @Test("full outcome の rejectReason がそのまま伝播する")
    func fullOutcomePropagatesRejectReason() {
        let outcome = ViewerLoadPipeline.Outcome.full(
            ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
            cache: nil
        )
        let render = OneShotRenderer.render(
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
        let render = OneShotRenderer.render(
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
        let render = OneShotRenderer.render(
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
        let render = OneShotRenderer.render(
            from: outcome, url: url, fileType: .code(language: "plaintext")
        )

        #expect(render.truncation.isTruncated == true)
        // 改行2個 + 末尾の途中行 1 = 3 行。
        #expect(render.truncation.lineCount == 3)
    }

    @Test("missing outcome は unsupportedFormat へ安全側で倒す")
    func missingOutcomeRejectsAsUnsupported() {
        let render = OneShotRenderer.render(
            from: .missing, url: URL(fileURLWithPath: "/tmp/gone.md"), fileType: .markdown
        )

        #expect(render.rejectReason == .unsupportedFormat)
        #expect(render.content.isEmpty)
    }
}
