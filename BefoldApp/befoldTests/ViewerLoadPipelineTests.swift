@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ViewerLoadPipeline.load(oneShotLoad:) が静的1回読込(QuickLook 等)経路で
/// dataHash 計算をスキップすることを、ViewerStore を経由せず直接検証する。
/// InMemoryFileReader を使うため実 FS 不要の unit テスト。
/// 実ローカル画像埋め込みキャッシュのウォームアップ検証は Integration へ移した。
@Suite
struct ViewerLoadPipelineTests {
    private let chunkedReaderFactory: ViewerLoadPipeline.ChunkedReaderFactory = { cache, fileType in
        StringChunkReader(cache: cache, respectsCSVQuotes: fileType.csvDelimiter != nil)
    }

    @Test("oneShotLoad: true では行指向ファイル(chunked)経路で dataHash が nil になる")
    func oneShotLoadSkipsHashForChunkedOutcome() async {
        let url = URL(fileURLWithPath: "/tmp/oneshot.log")
        let fileReader = InMemoryFileReader(files: [url.path: "line1\nline2\nline3\n"])
        let contentLoader = ContentLoader(fileReader: fileReader)

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .code(language: "plaintext"),
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: chunkedReaderFactory,
            oneShotLoad: true
        )

        guard case let .chunked(_, cache, _, _) = outcome else {
            Issue.record("chunked outcome を期待したが \(outcome) だった")
            return
        }
        #expect(cache.dataHash == nil)
    }

    @Test("oneShotLoad: true では非行指向ファイル(full)経路で dataHash が nil になる")
    func oneShotLoadSkipsHashForFullOutcome() async {
        let url = URL(fileURLWithPath: "/tmp/oneshot.md")
        let fileReader = InMemoryFileReader(files: [url.path: "# hello\n"])
        let contentLoader = ContentLoader(fileReader: fileReader)

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .markdown,
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: chunkedReaderFactory,
            oneShotLoad: true
        )

        guard case let .full(_, cache) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(cache?.dataHash == nil)
    }

    @Test("oneShotLoad: false(既定)では従来どおり dataHash が計算される(回帰なし)")
    func defaultLoadStillComputesHashForChunkedOutcome() async {
        let url = URL(fileURLWithPath: "/tmp/default-load.log")
        let fileReader = InMemoryFileReader(files: [url.path: "line1\nline2\n"])
        let contentLoader = ContentLoader(fileReader: fileReader)

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .code(language: "plaintext"),
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: chunkedReaderFactory
        )

        guard case let .chunked(_, cache, _, _) = outcome else {
            Issue.record("chunked outcome を期待したが \(outcome) だった")
            return
        }
        #expect(cache.dataHash != nil)
    }
}
