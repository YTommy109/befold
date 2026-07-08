@testable import befold
import Foundation
import Testing

@Suite
struct ViewerWebViewCoordinatorTests {
    @Test("ソース表示中はmarkdownのローカル画像参照をbase64に埋め込まない")
    func sourceModeDoesNotEmbedLocalImages() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerWebViewCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let imageURL = tempDir.appendingPathComponent("image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        let markdownURL = tempDir.appendingPathComponent("doc.md")
        let markdown = "# Title\n\n![alt](image.png)\n"

        let result = ViewerWebView.Coordinator.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: true
        )

        #expect(result == markdown)
    }

    @Test("レンダリング表示中はmarkdownのローカル画像参照をbase64に埋め込む")
    func renderedModeEmbedsLocalImages() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerWebViewCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let imageURL = tempDir.appendingPathComponent("image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        let markdownURL = tempDir.appendingPathComponent("doc.md")
        let markdown = "# Title\n\n![alt](image.png)\n"

        let result = ViewerWebView.Coordinator.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: false
        )

        #expect(result.contains("data:image/png;base64,"))
        #expect(!result.contains("(image.png)"))
    }
}
