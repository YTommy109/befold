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
        try ViewerLoadPipeline.defaultChunkedReaderFactory(cache, fileType)
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

    /// markdown はチャンク対象になったため(Issue #307)、full 経路の確認には
    /// チャンク非対応の型(html)を使う。
    @Test("oneShotLoad: true ではチャンク非対応ファイル(full)経路で dataHash が nil になる")
    func oneShotLoadSkipsHashForFullOutcome() async {
        let url = URL(fileURLWithPath: "/tmp/oneshot.html")
        let fileReader = InMemoryFileReader(files: [url.path: "<h1>hello</h1>\n"])
        let contentLoader = ContentLoader(fileReader: fileReader)

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .html,
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

    @Test("oneShotLoad: true ではバイナリ(full)経路で contentHash が nil になる")
    func oneShotLoadSkipsHashForBinaryOutcome() async {
        let url = URL(fileURLWithPath: "/tmp/oneshot.png")
        let fileReader = InMemoryFileReader()
        fileReader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47]), at: url)
        let contentLoader = ContentLoader(fileReader: fileReader)

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .image(mimeType: "image/png"),
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: chunkedReaderFactory,
            oneShotLoad: true
        )

        guard case let .full(loaded, _) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(loaded.contentHash == nil)
    }

    /// バイナリ(画像・PDF)は NormalizedTextCache を作らないため cache は nil のまま。
    /// 同一内容スキップに使う hash は LoadedContent 側が運ぶ。
    @Test("oneShotLoad: false(既定)ではバイナリ(full)経路で contentHash が計算される")
    func defaultLoadComputesHashForBinaryOutcome() async {
        let url = URL(fileURLWithPath: "/tmp/default-load.png")
        let fileReader = InMemoryFileReader()
        fileReader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47]), at: url)
        let contentLoader = ContentLoader(fileReader: fileReader)

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .image(mimeType: "image/png"),
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: chunkedReaderFactory
        )

        guard case let .full(loaded, cache) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(cache == nil)
        #expect(loaded.contentHash != nil)
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

    // MARK: - 非行指向のサイズ上限(TASK-72.6 の実測に基づく)

    /// 非行指向はチャンク読み込みが効かず全量を DOM 化するため、静的1回描画
    /// (QuickLook)では通常より厳しい上限を使う。実測では 4MB 以上で描画が
    /// 3 秒以内に終わらず、プレビューが長時間空白のままになった。
    @Test("oneShotLoad: true ではチャンク非対応の上限が 2MB に下がる")
    func oneShotLoadUsesSmallerLimitForNonLineOriented() async {
        let url = URL(fileURLWithPath: "/tmp/big.html")
        let content = String(repeating: "a", count: ContentLoader.maxOneShotTextFileSizeBytes + 1)
        let fileReader = InMemoryFileReader(files: [url.path: content])

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .html,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            oneShotLoad: true
        )

        guard case let .full(loaded, _) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(loaded.rejectReason == .fileTooLarge)
    }

    /// 通常のアプリ本体(oneShotLoad: false)は従来どおり 10MB まで扱う。
    /// QuickLook 側の上限を下げたことで本体の挙動が変わっていないことを担保する。
    @Test("oneShotLoad: false では 2MB 超のチャンク非対応でも従来どおり読み込める")
    func regularLoadKeepsLargerLimitForNonLineOriented() async {
        let url = URL(fileURLWithPath: "/tmp/big.html")
        let content = String(repeating: "a", count: ContentLoader.maxOneShotTextFileSizeBytes + 1)
        let fileReader = InMemoryFileReader(files: [url.path: content])

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .html,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            oneShotLoad: false
        )

        guard case let .full(loaded, _) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(loaded.rejectReason == nil)
    }

    /// 行指向(コード/CSV)は先頭チャンクしか描画しないため、実測でも 99MB で
    /// 0.33 秒・WebContent 118MB に収まっていた。上限を下げてはいけない。
    @Test("oneShotLoad: true でも行指向は 2MB 超を拒否しない")
    func oneShotLoadKeepsChunkedLimitForLineOriented() async {
        let url = URL(fileURLWithPath: "/tmp/big.py")
        let content = String(repeating: "x\n", count: ContentLoader.maxOneShotTextFileSizeBytes)
        let fileReader = InMemoryFileReader(files: [url.path: content])

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .code(language: "python"),
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            oneShotLoad: true
        )

        guard case .chunked = outcome else {
            Issue.record("chunked outcome を期待したが \(outcome) だった")
            return
        }
    }

    @Test("hasDeclaredHTMLCharset は charset 宣言の有無とファイル種別で決まる", arguments: [
        // (ファイル名, 種別, 内容, 期待値)
        ("undeclared.html", FileType.html, "<h1>hello</h1>", Bool?.some (false)), // charset 宣言の無い HTML
        (
            "declared.html", .html,
            "<html><head><meta charset=\"UTF-8\"></head><body>hello</body></html>", true
        ), // meta charset 宣言のある HTML
        ("plain.mmd", .mmd, "graph TD;A-->B;", nil), // HTML 以外は常に nil
    ])
    func loadReportsHasDeclaredHTMLCharset(
        name: String, fileType: FileType, contents: String, expected: Bool?
    ) async {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        let fileReader = InMemoryFileReader(files: [url.path: contents])

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: fileType,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory
        )

        guard case let .full(loaded, _) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(loaded.hasDeclaredHTMLCharset == expected)
    }
}
