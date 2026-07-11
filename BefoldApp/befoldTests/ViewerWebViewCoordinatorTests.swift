@testable import befold
import Foundation
import Testing

@Suite
struct ViewerWebViewCoordinatorTests {
    @Test("ソース表示中はmarkdownのローカル画像参照をbase64に埋め込まない")
    func sourceModeDoesNotEmbedLocalImages() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let markdownURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = "# Title\n\n![alt](image.png)\n"

        let result = ViewerWebView.Coordinator.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: true
        )

        #expect(result == markdown)
    }

    @Test("レンダリング表示中はmarkdownのローカル画像参照をbase64に埋め込む")
    func renderedModeEmbedsLocalImages() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let markdownURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = "# Title\n\n![alt](image.png)\n"

        let result = ViewerWebView.Coordinator.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: false
        )

        #expect(result.contains("data:image/png;base64,"))
        #expect(!result.contains("(image.png)"))
    }

    private static let fileA = URL(fileURLWithPath: "/tmp/a.md")
    private static let fileB = URL(fileURLWithPath: "/tmp/b.md")

    struct SwitchCase: Sendable, CustomTestStringConvertible {
        let name: String
        let filePath: URL
        let isSourceMode: Bool
        let lastRenderedFilePath: URL?
        let lastIsSourceMode: Bool?
        let expected: Bool
        var testDescription: String {
            name
        }
    }

    static let switchCases: [SwitchCase] = [
        SwitchCase(
            name: "同一ファイル・同一モードのライブリロード/行番号トグル",
            filePath: fileA, isSourceMode: false,
            lastRenderedFilePath: fileA, lastIsSourceMode: false, expected: false
        ),
        SwitchCase(
            name: "ファイル切替",
            filePath: fileA, isSourceMode: false,
            lastRenderedFilePath: fileB, lastIsSourceMode: false, expected: true
        ),
        SwitchCase(
            name: "モード切替(レンダリング→ソース)",
            filePath: fileA, isSourceMode: true,
            lastRenderedFilePath: fileA, lastIsSourceMode: false, expected: true
        ),
        SwitchCase(
            name: "初回描画(lastRenderedFilePath 未設定)",
            filePath: fileA, isSourceMode: false,
            lastRenderedFilePath: nil, lastIsSourceMode: false, expected: true
        ),
        SwitchCase(
            name: "初回描画(lastIsSourceMode 未設定)",
            filePath: fileA, isSourceMode: false,
            lastRenderedFilePath: fileA, lastIsSourceMode: nil, expected: true
        ),
    ]

    @Test("ファイル/モードが変わらない再描画は切替として扱わない", arguments: switchCases)
    func isFileOrModeSwitch(_ testCase: SwitchCase) {
        let result = ViewerWebView.Coordinator.isFileOrModeSwitch(
            filePath: testCase.filePath, isSourceMode: testCase.isSourceMode,
            lastRenderedFilePath: testCase.lastRenderedFilePath, lastIsSourceMode: testCase.lastIsSourceMode
        )

        #expect(result == testCase.expected)
    }
}
