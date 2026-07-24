@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ViewerLoadPipeline.load(oneShotLoad:) が静的1回読込(QuickLook 等)経路で
/// dataHash 計算をスキップすることを、ViewerStore を経由せず直接検証する。
/// InMemoryFileReader を使うため実 FS 不要の unit テスト。
/// 画像埋め込みキャッシュのウォームアップも imageEmbedder 注入(TASK-116.12)で
/// InMemoryFileReader によりモック化できるようになったため unit で検証する。
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

    @Test("embedLocalImages: true でロードすると画像埋め込みキャッシュが温まり、その後の埋め込み呼び出しは画像を再読込しない")
    func loadWarmsMarkdownImageEmbedCache() async {
        let dir = URL(fileURLWithPath: "/tmp/pipeline-warm")
        let imageURL = dir.appendingPathComponent("warm.png")
        let markdownURL = dir.appendingPathComponent("doc.md")
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let fileReader = InMemoryFileReader(files: [markdownURL.path: "![alt](warm.png)"])
        fileReader.setDataFile(pngData, at: imageURL)
        let embedder = MarkdownImageEmbedder(fileReader: fileReader)

        _ = await ViewerLoadPipeline.load(
            resolved: markdownURL,
            fileType: .markdown,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            embedLocalImages: true,
            imageEmbedder: embedder
        )

        // ウォームアップ後に画像の読み込みを失敗させても、キャッシュ済み data URI が返る。
        // (サイズ・更新日時は不変なのでキャッシュがヒットし readData を呼ばない)= 再読込していない。
        fileReader.setReadError(true, at: imageURL)
        let expectedURI = "data:image/png;base64,\(pngData.base64EncodedString())"
        let result = embedder.embedLocalImages(in: "![alt](warm.png)", baseURL: markdownURL)

        #expect(result == "![alt](\(expectedURI))")
    }

    @Test("embedLocalImages: false でロードすると画像埋め込みキャッシュを温めない")
    func loadWithEmbedLocalImagesDisabledDoesNotWarmCache() async {
        let dir = URL(fileURLWithPath: "/tmp/pipeline-cold")
        let imageURL = dir.appendingPathComponent("cold.png")
        let markdownURL = dir.appendingPathComponent("doc.md")
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let fileReader = InMemoryFileReader(files: [markdownURL.path: "![alt](cold.png)"])
        fileReader.setDataFile(pngData, at: imageURL)
        let embedder = MarkdownImageEmbedder(fileReader: fileReader)

        _ = await ViewerLoadPipeline.load(
            resolved: markdownURL,
            fileType: .markdown,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            embedLocalImages: false,
            imageEmbedder: embedder
        )

        // キャッシュが温まっていなければ、読み込み失敗時に埋め込みできず原文のまま。
        fileReader.setReadError(true, at: imageURL)
        let markdown = "![alt](cold.png)"
        let result = embedder.embedLocalImages(in: markdown, baseURL: markdownURL)

        #expect(result == markdown)
    }
}
