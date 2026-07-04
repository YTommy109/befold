import Foundation
@testable import mmdview
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

    @Test
    func initialZoomScriptEmbedsValue() {
        #expect(ViewerBridge.initialZoomScript(1.5) == "window._mmdInitialZoom = 1.5;")
    }

    @Test
    func systemFontSizeScriptEmbedsValue() {
        #expect(ViewerBridge.systemFontSizeScript(13.0) == "window._mmdSystemFontSize = 13.0;")
    }

    /// ViewerBridge が参照する JS 関数・メッセージ名が viewer.html に実在することを
    /// リポジトリ内のソースを読んで検証する(ブリッジ契約のドリフト検知)。
    @Test("ViewerBridge の関数名が viewer.html に定義されている")
    func bridgeFunctionsExistInViewerHTML() throws {
        let html = try String(contentsOf: resourceURL("viewer.html"), encoding: .utf8)

        #expect(html.contains("async function render(content, type)"))
        #expect(html.contains("function showDeletedBanner()"))
        #expect(html.contains("function _mmdZoomIn()"))
        #expect(html.contains("function _mmdZoomOut()"))
        #expect(html.contains("function _mmdZoomReset()"))
        #expect(html.contains("messageHandlers.\(ViewerBridge.zoomChangedMessageName)"))
        #expect(html.contains("window._mmdInitialZoom"))
        #expect(html.contains("window._mmdSystemFontSize"))
    }

    @Test("viewer.js の ZOOM_MIN / ZOOM_MAX が ZoomStore の範囲と一致する")
    func zoomRangeMatchesZoomStore() throws {
        let js = try String(contentsOf: resourceURL("viewer.js"), encoding: .utf8)

        #expect(js.contains("var ZOOM_MIN = \(ZoomStore.minZoom);"))
        #expect(js.contains("var ZOOM_MAX = \(ZoomStore.maxZoom);"))
    }

    /// mmdviewTests/ から見た mmdview/Resources/ 内のリソース URL を返す。
    private func resourceURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // mmdviewTests
            .deletingLastPathComponent() // MmdviewApp
            .appendingPathComponent("mmdview/Resources/\(name)")
    }
}
