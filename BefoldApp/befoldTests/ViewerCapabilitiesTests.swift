@testable import befold
import Foundation
import Testing

/// 能力(ViewerCapabilities)が提示状態から導出されること(ADR 0002 段 2)を検証する。
@Suite
struct ViewerCapabilitiesTests {
    private func makeCapabilities(
        isPresentingDocument: Bool = true,
        isRejected: Bool = false,
        isRenderable: Bool = true,
        isBinaryContent: Bool = false,
        showsCodeContent: Bool = true,
        supportsSourceMode: Bool = true,
        isDirectHTMLMode: Bool = false
    ) -> ViewerCapabilities {
        ViewerCapabilities(
            isPresentingDocument: isPresentingDocument,
            isRejected: isRejected,
            isRenderable: isRenderable,
            isBinaryContent: isBinaryContent,
            showsCodeContent: showsCodeContent,
            supportsSourceMode: supportsSourceMode,
            isDirectHTMLMode: isDirectHTMLMode
        )
    }

    @Test("フォルダー一覧の表示中は、見えない文書に対する操作をすべて許さない")
    func deniesEverythingWhilePresentingFolder() {
        let capabilities = makeCapabilities(isPresentingDocument: false)

        #expect(!capabilities.canPrint)
        #expect(!capabilities.canFind)
        #expect(!capabilities.canZoom)
        #expect(!capabilities.canToggleSourceMode)
        #expect(!capabilities.canSelectPreviewMode)
        #expect(!capabilities.canSelectSourceMode)
        #expect(!capabilities.canToggleLineNumbers)
        #expect(!capabilities.canBookmark)
    }

    @Test("文書を提示していれば、種別に応じた操作が許される")
    func allowsDocumentCommandsWhilePresentingDocument() {
        let capabilities = makeCapabilities()

        #expect(capabilities.canPrint)
        #expect(capabilities.canFind)
        #expect(capabilities.canZoom)
        #expect(capabilities.canToggleSourceMode)
        #expect(capabilities.canBookmark)
    }

    @Test("HTML 直接ロード中は検索だけを止め、他は止めない")
    func disablesOnlyFindInDirectHTMLMode() {
        let capabilities = makeCapabilities(isDirectHTMLMode: true)

        #expect(!capabilities.canFind)
        #expect(capabilities.canPrint)
        #expect(capabilities.canZoom)
    }

    @Test("表示できないファイルでは文書操作を許さない")
    func deniesCommandsForRejectedFile() {
        let capabilities = makeCapabilities(isRejected: true)

        #expect(!capabilities.canPrint)
        #expect(!capabilities.canFind)
        #expect(!capabilities.canZoom)
        #expect(!capabilities.canToggleSourceMode)
    }

    @Test("モード切替は種別で決まる: 画像・PDF はソース側、プレビュー不可の種別はプレビュー側を落とす")
    func modeSelectionFollowsFileType() {
        #expect(!makeCapabilities(isBinaryContent: true).canSelectSourceMode)
        #expect(makeCapabilities(isBinaryContent: true).canSelectPreviewMode)
        #expect(!makeCapabilities(isRenderable: false).canSelectPreviewMode)
        #expect(makeCapabilities(isRenderable: false).canSelectSourceMode)
    }

    @Test("行番号はソース相当の内容を表示しているときだけ切り替えられる")
    func lineNumbersFollowCodeContent() {
        #expect(makeCapabilities(showsCodeContent: true).canToggleLineNumbers)
        #expect(!makeCapabilities(showsCodeContent: false).canToggleLineNumbers)
    }

    @Test("何も提示していない既定値はすべて不可")
    func noneDeniesEverything() {
        #expect(ViewerCapabilities.none == ViewerCapabilities(
            isPresentingDocument: false, isRejected: false, isRenderable: false,
            isBinaryContent: false, showsCodeContent: false, supportsSourceMode: false,
            isDirectHTMLMode: false
        ))
        #expect(!ViewerCapabilities.none.canPrint)
    }
}

extension ViewerCapabilities {
    /// すべて可能な状態。コマンド実行側のテストが「能力あり」を簡潔に表すために使う。
    static let allEnabledForTesting = ViewerCapabilities(
        isPresentingDocument: true,
        isRejected: false,
        isRenderable: true,
        isBinaryContent: false,
        showsCodeContent: true,
        supportsSourceMode: true,
        isDirectHTMLMode: false
    )
}
