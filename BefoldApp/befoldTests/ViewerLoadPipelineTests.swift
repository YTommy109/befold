@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ViewerLoadPipeline.load(oneShotLoad:) が静的1回読込(QuickLook 等)経路で
/// dataHash 計算をスキップすることを、ViewerStore を経由せず直接検証する。
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

    // MARK: - markdown ローカル画像埋め込みキャッシュのウォームアップ

    private func withReadPermissionRemoved<T>(at url: URL, _ body: () throws -> T) rethrows -> T {
        let original = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer {
            if let original {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: original], ofItemAtPath: url.path
                )
            }
        }
        return try body()
    }

    @Test("embedLocalImages: true でロードすると画像埋め込みキャッシュが温まり、その後の埋め込み呼び出しは画像を再読込しない")
    func loadWarmsMarkdownImageEmbedCache() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let imageURL = try tmp.file(named: "warm.png", data: pngData)
        let markdownURL = try tmp.file(named: "doc.md", contents: "![alt](warm.png)")
        let fileReader = DefaultFileReader()

        _ = await ViewerLoadPipeline.load(
            resolved: markdownURL,
            fileType: .markdown,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            embedLocalImages: true
        )

        let expectedURI = "data:image/png;base64,\(pngData.base64EncodedString())"
        let result = withReadPermissionRemoved(at: imageURL) {
            MarkdownImageEmbedder.shared.embedLocalImages(
                in: "![alt](warm.png)", baseURL: markdownURL
            )
        }

        #expect(result == "![alt](\(expectedURI))")
    }

    @Test("embedLocalImages: false でロードすると画像埋め込みキャッシュを温めない")
    func loadWithEmbedLocalImagesDisabledDoesNotWarmCache() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let imageURL = try tmp.file(named: "cold.png", data: pngData)
        let markdownURL = try tmp.file(named: "doc.md", contents: "![alt](cold.png)")
        let fileReader = DefaultFileReader()

        _ = await ViewerLoadPipeline.load(
            resolved: markdownURL,
            fileType: .markdown,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            embedLocalImages: false
        )

        let markdown = "![alt](cold.png)"
        let result = withReadPermissionRemoved(at: imageURL) {
            MarkdownImageEmbedder.shared.embedLocalImages(in: markdown, baseURL: markdownURL)
        }

        #expect(result == markdown)
    }
}
