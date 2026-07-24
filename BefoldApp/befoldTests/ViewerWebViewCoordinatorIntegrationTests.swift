@testable import befold
import BefoldKit
import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// markdown のローカル画像参照の base64 埋め込み(および短絡による非埋め込み)を検証する。
/// いずれも実 PNG ファイルが存在する状態を前提に renderableContent の挙動を確認するが、
/// MarkdownImageEmbedder に fileReader 注入口が無いため製品変更なしにはモック化できず Integration。
/// (非埋め込みケースも「実ファイルが存在してもなお埋め込まない」ことの検証であり実 FS が意味を持つ)
@Suite
struct ViewerWebViewCoordinatorIntegrationTests {
    @Test("レンダリング表示中はmarkdownのローカル画像参照をbase64に埋め込む")
    func renderedModeEmbedsLocalImages() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let markdownURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = "# Title\n\n![alt](image.png)\n"

        let result = ViewerRenderer.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: false
        )

        #expect(result.contains("data:image/png;base64,"))
        #expect(!result.contains("(image.png)"))
    }

    @Test("ソース表示中はmarkdownのローカル画像参照をbase64に埋め込まない")
    func sourceModeDoesNotEmbedLocalImages() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let markdownURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = "# Title\n\n![alt](image.png)\n"

        let result = ViewerRenderer.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: true
        )

        #expect(result == markdown)
    }

    @Test("embedImages: false のときはレンダリング表示中でもmarkdownのローカル画像参照を埋め込まない")
    func embedImagesDisabledDoesNotEmbedLocalImages() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let markdownURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = "# Title\n\n![alt](image.png)\n"

        let result = ViewerRenderer.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: false,
            embedImages: false
        )

        #expect(result == markdown)
    }
}
