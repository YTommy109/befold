@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// markdown ローカル画像埋め込みキャッシュのウォームアップを検証する。
/// 実 PNG ファイル・DefaultFileReader・実ファイルパーミッション操作・MarkdownImageEmbedder.shared
/// を踏むため製品変更なしにはモック化できず Integration。
@Suite
struct ViewerLoadPipelineIntegrationTests {
    private let chunkedReaderFactory: ViewerLoadPipeline.ChunkedReaderFactory = { cache, fileType in
        StringChunkReader(cache: cache, respectsCSVQuotes: fileType.csvDelimiter != nil)
    }

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
