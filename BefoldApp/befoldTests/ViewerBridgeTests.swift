@testable import befold
import Foundation
import Testing

@Suite
@MainActor // ZoomStore(@MainActor)の static 定数を参照するため
struct ViewerBridgeTests {
    @Test("render 呼び出しの content が JSON エスケープされる")
    func renderScriptEscapesContentAsJSON() throws {
        let content = "graph TD; A[\"x\"]\n'; alert(1); '"

        let script = try #require(ViewerBridge.renderScript(content: content, fileType: .mmd))

        #expect(script.hasPrefix("render(\""))
        #expect(script.hasSuffix("\", 'mmd')"))
        // 改行・引用符は JSON エスケープされ、生の改行は script に現れない
        #expect(!script.contains("\n"))
    }

    @Test
    func renderScriptUsesFileTypeJSValue() throws {
        let script = try #require(ViewerBridge.renderScript(content: "# Hi", fileType: .markdown))

        #expect(script.hasSuffix("\", 'md')"))
    }

    @Test("code タイプは第 3 引数に言語名を渡す")
    func renderScriptAppendsLanguageForCode() throws {
        let script = try #require(
            ViewerBridge.renderScript(content: "let x = 1", fileType: .code(language: "swift"))
        )

        #expect(script.hasSuffix("\", 'code', 'swift')"))
    }

    @Test("csv タイプは第 3 引数に delimiter を渡す")
    func renderScriptAppendsDelimiterForCsv() throws {
        let script = try #require(
            ViewerBridge.renderScript(content: "a,b\n1,2", fileType: .csv(delimiter: ","))
        )
        #expect(script.hasSuffix("\", 'csv', ',')"))
    }

    @Test("tsv タイプは第 3 引数にタブ delimiter を渡す")
    func renderScriptAppendsTabDelimiterForTsv() throws {
        let script = try #require(
            ViewerBridge.renderScript(content: "a\tb\n1\t2", fileType: .csv(delimiter: "\t"))
        )
        #expect(script.hasSuffix("\", 'csv', '\\t')"))
    }

    @Test("mmd / md は従来どおり 2 引数のまま（言語引数を付けない）")
    func renderScriptOmitsLanguageForNonCode() throws {
        let mmd = try #require(ViewerBridge.renderScript(content: "graph TD", fileType: .mmd))
        let md = try #require(ViewerBridge.renderScript(content: "# Hi", fileType: .markdown))

        #expect(mmd.hasSuffix("\", 'mmd')"))
        #expect(md.hasSuffix("\", 'md')"))
    }

    @Test
    func initialZoomScriptEmbedsValue() {
        #expect(ViewerBridge.initialZoomScript(1.5) == "window._mmdInitialZoom = 1.5;")
    }

    @Test
    func systemFontSizeScriptEmbedsValue() {
        #expect(ViewerBridge.systemFontSizeScript(13.0) == "window._mmdSystemFontSize = 13.0;")
    }

    @Test("applyZoomScript は倍率注入と _mmdInitZoom() 呼び出しを組み合わせる")
    func applyZoomScriptInjectsValueAndInvokesInit() {
        #expect(ViewerBridge.applyZoomScript(1.5) == "window._mmdInitialZoom = 1.5; _mmdInitZoom();")
    }

    @Test("svg タイプは 2 引数のまま（言語引数を付けない）")
    func renderScriptOmitsLanguageForSvg() throws {
        let script = try #require(ViewerBridge.renderScript(content: "<svg></svg>", fileType: .svg))
        #expect(script.hasSuffix("\", 'svg')"))
    }

    @Test("html タイプは 2 引数のまま（言語引数を付けない）")
    func renderScriptOmitsLanguageForHtml() throws {
        let script = try #require(ViewerBridge.renderScript(content: "<html></html>", fileType: .html))
        #expect(script.hasSuffix("\", 'html')"))
    }

    @Test("image タイプは第 3 引数に MIME タイプを渡す")
    func renderScriptAppendsMimeTypeForImage() throws {
        let script = try #require(
            ViewerBridge.renderScript(content: "base64data", fileType: .image(mimeType: "image/png"))
        )
        #expect(script.hasSuffix("\", 'image', 'image/png')"))
    }

    @Test("pdf タイプは 2 引数のまま")
    func renderScriptOmitsLangForPdf() throws {
        let script = try #require(
            ViewerBridge.renderScript(content: "base64data", fileType: .pdf)
        )
        #expect(script.hasSuffix("\", 'pdf')"))
    }

    @Test("viewModeScript がモード文字列を埋め込む")
    func viewModeScriptEmbedsMode() {
        #expect(ViewerBridge.viewModeScript(.source) == "setViewMode('source')")
        #expect(ViewerBridge.viewModeScript(.rendered) == "setViewMode('rendered')")
    }

    @Test("lineNumbersScript がブール値を埋め込む")
    func lineNumbersScriptEmbedsBool() {
        #expect(ViewerBridge.lineNumbersScript(true) == "setLineNumbers(true)")
        #expect(ViewerBridge.lineNumbersScript(false) == "setLineNumbers(false)")
    }

    /// ViewerBridge が参照する JS 関数・メッセージ名が viewer.html に実在することを
    /// リポジトリ内のソースを読んで検証する(ブリッジ契約のドリフト検知)。
    @Test("ViewerBridge の関数名が viewer.html に定義されている")
    func bridgeFunctionsExistInViewerHTML() throws {
        let html = try String(contentsOf: resourceURL("viewer.html"), encoding: .utf8)

        #expect(html.contains("async function render(content, type, lang)"))
        #expect(html.contains("function showDeletedBanner()"))
        #expect(html.contains("function _mmdZoomIn()"))
        #expect(html.contains("function _mmdZoomOut()"))
        #expect(html.contains("function _mmdZoomReset()"))
        #expect(html.contains("messageHandlers.\(ViewerBridge.zoomChangedMessageName)"))
        #expect(html.contains("_MSG_REFERENCE_ACTIVATED = '\(ViewerBridge.referenceActivatedMessageName)'"))
        #expect(html.contains("messageHandlers[_MSG_REFERENCE_ACTIVATED]"))
        #expect(html.contains("window._mmdInitialZoom"))
        #expect(html.contains("window._mmdSystemFontSize"))
        #expect(html.contains("function setViewMode(mode)"))
        #expect(html.contains("function _mmdInitZoom()"))
        #expect(html.contains("function setLineNumbers(show)"))
    }

    @Test("viewer.js の ZOOM_MIN / ZOOM_MAX が ZoomStore の範囲と一致する")
    func zoomRangeMatchesZoomStore() throws {
        let js = try String(contentsOf: resourceURL("viewer.js"), encoding: .utf8)

        #expect(js.contains("var ZOOM_MIN = \(ZoomStore.minZoom);"))
        #expect(js.contains("var ZOOM_MAX = \(ZoomStore.maxZoom);"))
    }

    /// befoldTests/ から見た befold/Resources/ 内のリソース URL を返す。
    private func resourceURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests
            .deletingLastPathComponent() // BefoldApp
            .appendingPathComponent("befold/Resources/\(name)")
    }
}
