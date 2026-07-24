@testable import befold
import BefoldKit
import BefoldRenderKit
import BefoldTestSupport
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

        let result = ViewerRenderer.renderableContent(
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

        let result = ViewerRenderer.renderableContent(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: false
        )

        #expect(result.contains("data:image/png;base64,"))
        #expect(!result.contains("(image.png)"))
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

    struct DirectHTMLCase: Sendable, CustomTestStringConvertible {
        let name: String
        let fileType: FileType
        let isSourceMode: Bool
        let hasFilePath: Bool
        let features: RendererFeatures
        let expected: Bool
        var testDescription: String {
            name
        }
    }

    private static let directHTMLURL = URL(fileURLWithPath: "/tmp/page.html")

    static let directHTMLCases: [DirectHTMLCase] = [
        DirectHTMLCase(
            name: "html・レンダリング表示・ファイル有り・allowDirectHTML有効 → 直接HTMLモードに入る",
            fileType: .html, isSourceMode: false, hasFilePath: true,
            features: .allEnabled, expected: true
        ),
        DirectHTMLCase(
            name: "allowDirectHTML無効 → 条件を満たしても直接HTMLモードに入らない",
            fileType: .html, isSourceMode: false, hasFilePath: true,
            features: RendererFeatures(allowDirectHTML: false, embedImages: true), expected: false
        ),
        DirectHTMLCase(
            name: "ソース表示中は直接HTMLモードに入らない",
            fileType: .html, isSourceMode: true, hasFilePath: true,
            features: .allEnabled, expected: false
        ),
        DirectHTMLCase(
            name: "html以外は直接HTMLモードに入らない",
            fileType: .markdown, isSourceMode: false, hasFilePath: true,
            features: .allEnabled, expected: false
        ),
        DirectHTMLCase(
            name: "filePathがnilなら直接HTMLモードに入らない",
            fileType: .html, isSourceMode: false, hasFilePath: false,
            features: .allEnabled, expected: false
        ),
    ]

    @Test("直接HTMLモードへの遷移可否はallowDirectHTMLフラグとファイル種別/表示モードで決まる", arguments: directHTMLCases)
    func shouldEnterDirectHTMLMode(_ testCase: DirectHTMLCase) {
        let result = ViewerRenderer.shouldEnterDirectHTMLMode(
            fileType: testCase.fileType, isSourceMode: testCase.isSourceMode,
            filePath: testCase.hasFilePath ? Self.directHTMLURL : nil,
            features: testCase.features
        )

        #expect(result == testCase.expected)
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
        let result = ViewerRenderer.isFileOrModeSwitch(
            filePath: testCase.filePath, isSourceMode: testCase.isSourceMode,
            lastRenderedFilePath: testCase.lastRenderedFilePath, lastIsSourceMode: testCase.lastIsSourceMode
        )

        #expect(result == testCase.expected)
    }

    // MARK: - messageHandlerNames

    @Test("allowsInteractiveBridging: true(既定)では referenceActivated/loadMoreLines を含む全ハンドラを登録する")
    func messageHandlerNamesIncludesAllWhenInteractiveBridgingEnabled() {
        let names = ViewerRenderer.messageHandlerNames(for: .allEnabled)

        #expect(names.contains(ViewerBridge.referenceActivatedMessageName))
        #expect(names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(names.contains(ViewerBridge.zoomChangedMessageName))
        #expect(names.contains(ViewerBridge.findOptionsChangedMessageName))
        #expect(names.contains(ViewerBridge.scrollPositionChangedMessageName))
        #expect(names.count == 5)
    }

    @Test("allowsInteractiveBridging: false では referenceActivated/loadMoreLines を登録しない(多層防御)")
    func messageHandlerNamesExcludesInteractiveHandlersWhenDisabled() {
        let features = RendererFeatures(
            allowDirectHTML: false, embedImages: false, allowsInteractiveBridging: false
        )
        let names = ViewerRenderer.messageHandlerNames(for: features)

        #expect(!names.contains(ViewerBridge.referenceActivatedMessageName))
        #expect(!names.contains(ViewerBridge.loadMoreLinesMessageName))
        // ズーム・検索・スクロール位置通知は静的1回読込でも安全なため登録を維持する。
        #expect(names.contains(ViewerBridge.zoomChangedMessageName))
        #expect(names.contains(ViewerBridge.findOptionsChangedMessageName))
        #expect(names.contains(ViewerBridge.scrollPositionChangedMessageName))
        #expect(names.count == 3)
    }
}
