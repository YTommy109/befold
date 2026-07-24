@testable import befold
import BefoldKit
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

    /// FileType ごとに renderScript の suffix (type, lang) が正しく生成されること。
    @Test(arguments: [
        (content: "# Hi", fileType: FileType.markdown, expectedSuffix: "\", 'md')"),
        (content: "let x = 1", fileType: FileType.code(language: "swift"), expectedSuffix: "\", 'code', 'swift')"),
        (content: "a,b\n1,2", fileType: FileType.csv(delimiter: ","), expectedSuffix: "\", 'csv', ',')"),
        (content: "a\tb\n1\t2", fileType: FileType.csv(delimiter: "\t"), expectedSuffix: "\", 'csv', '\\t')"),
        (content: "graph TD", fileType: FileType.mmd, expectedSuffix: "\", 'mmd')"),
        (content: "<svg></svg>", fileType: FileType.svg, expectedSuffix: "\", 'svg')"),
        (content: "<html></html>", fileType: FileType.html, expectedSuffix: "\", 'html')"),
        (
            content: "base64data", fileType: FileType.image(mimeType: "image/png"),
            expectedSuffix: "\", 'image', 'image/png')"
        ),
        (content: "base64data", fileType: FileType.pdf, expectedSuffix: "\", 'pdf')"),
    ])
    func renderScriptSuffixByFileType(content: String, fileType: FileType, expectedSuffix: String) throws {
        let script = try #require(ViewerBridge.renderScript(content: content, fileType: fileType))
        #expect(script.hasSuffix(expectedSuffix))
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

    @Test("restoreScrollPositionScript がスクロール位置を埋め込む")
    func restoreScrollPositionScriptEmbedsValue() {
        #expect(
            ViewerBridge.restoreScrollPositionScript(150.5)
                == "_mmdSetRestoreScroll(150.5)"
        )
    }

    @Test("restoreScrollPositionScript は 0 のときも正しく生成する")
    func restoreScrollPositionScriptHandlesZero() {
        #expect(ViewerBridge.restoreScrollPositionScript(0) == "_mmdSetRestoreScroll(0.0)")
    }

    /// NaN/Infinity は不正な JS リテラルになるため 0 にフォールバックすること。
    @Test("restoreScrollPositionScript は非有限値を 0 にフォールバックする", arguments: [
        Double.nan, Double.infinity, -Double.infinity,
    ])
    func restoreScrollPositionScriptFallsBackToZeroForNonFinite(position: Double) {
        #expect(ViewerBridge.restoreScrollPositionScript(position) == "_mmdSetRestoreScroll(0.0)")
    }

    @Test("scrollPositionChangedMessageName が固定値である")
    func scrollPositionChangedMessageNameIsFixed() {
        #expect(ViewerBridge.scrollPositionChangedMessageName == "scrollPositionChanged")
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

    @Test("appendChunkScript は JSON エスケープされた appendChunk 呼び出しを生成する")
    func appendChunkScriptGeneratesCall() throws {
        let chunk = "line1\nline2\n\"quoted\""
        let script = try #require(
            ViewerBridge.appendChunkScript(chunk: chunk, fileType: .csv(delimiter: ","))
        )
        #expect(script.hasPrefix("appendChunk("))
        #expect(script.contains("'csv'"))
        #expect(!script.contains("\n"))
    }

    @Test("truncatedScript にカウントを渡せる")
    func truncatedScriptWithLineCount() {
        let script = ViewerBridge.truncatedScript(true, lineCount: 1000, failed: false)
        #expect(script == "_mmdSetTruncated(true, 1000, false)")
    }

    @Test("truncatedScript false はカウント 0")
    func truncatedScriptFalse() {
        let script = ViewerBridge.truncatedScript(false, lineCount: 0, failed: false)
        #expect(script == "_mmdSetTruncated(false, 0, false)")
    }

    @Test("truncatedScript は failed=true を渡せる(読込エラー時のバナー切替用)")
    func truncatedScriptFailed() {
        let script = ViewerBridge.truncatedScript(true, lineCount: 5, failed: true)
        #expect(script == "_mmdSetTruncated(true, 5, true)")
    }

    @Test
    func loadMoreLinesMessageNameIsDefined() {
        #expect(!ViewerBridge.loadMoreLinesMessageName.isEmpty)
    }

    @Test("hostFeaturesScript が window._mmdHostFeatures への代入文を生成する")
    func hostFeaturesScriptAssignsHostFeaturesGlobal() throws {
        let script = ViewerBridge.hostFeaturesScript(
            loadMore: true, spaceScroll: false, referenceActivation: false
        )

        #expect(script.hasPrefix("window._mmdHostFeatures = "))
        #expect(script.hasSuffix(";"))

        let jsonPart = script
            .replacingOccurrences(of: "window._mmdHostFeatures = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        #expect(decoded["loadMore"] == true)
        #expect(decoded["spaceScroll"] == false)
        #expect(decoded["referenceActivation"] == false)
    }

    @Test("hostFeaturesScript のデフォルトは全機能とも有効")
    func hostFeaturesScriptDefaultsToAllEnabled() throws {
        let script = ViewerBridge.hostFeaturesScript()

        let jsonPart = script
            .replacingOccurrences(of: "window._mmdHostFeatures = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        #expect(decoded["loadMore"] == true)
        #expect(decoded["spaceScroll"] == true)
        #expect(decoded["referenceActivation"] == true)
    }

    @Test("bannerStringsScript が window._mmdBannerStrings への代入文を生成する")
    func bannerStringsScriptAssignsBannerStringsGlobal() {
        let script = ViewerBridge.bannerStringsScript()
        #expect(script.hasPrefix("window._mmdBannerStrings = "))
        #expect(script.hasSuffix(";"))
    }

    @Test("openFindScript が固定の呼び出し文字列である")
    func openFindScriptIsFixedCall() {
        #expect(ViewerBridge.openFindScript == "_mmdOpenFind()")
    }

    @Test("findOptionsChangedMessageName が固定値である")
    func findOptionsChangedMessageNameIsFixed() {
        #expect(ViewerBridge.findOptionsChangedMessageName == "findOptionsChanged")
    }

    @Test("initialFindOptionsScript がトグル値を埋め込む")
    func initialFindOptionsScriptEmbedsValues() {
        let options = ViewerBridge.FindOptions(caseSensitive: true, wholeWord: false, useRegex: true)

        #expect(
            ViewerBridge.initialFindOptionsScript(options)
                == "window._mmdInitialFindOptions = { caseSensitive: true, wholeWord: false, useRegex: true };"
        )
    }

    @Test("findStringsScript が window._mmdFindStrings への代入文を生成する")
    func findStringsScriptAssignsFindStringsGlobal() {
        let script = ViewerBridge.findStringsScript()

        #expect(script.hasPrefix("window._mmdFindStrings = "))
        #expect(script.hasSuffix(";"))
    }

    @Test("findStringsScript が全キーを含む妥当な JSON を生成する")
    func findStringsScriptProducesValidJSONWithAllKeys() throws {
        let script = ViewerBridge.findStringsScript()

        let jsonPart = script
            .replacingOccurrences(of: "window._mmdFindStrings = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        let expectedKeys = [
            "placeholder", "previous", "next", "matchCase",
            "matchWholeWord", "useRegularExpression", "close", "withinDisplayedRange",
        ]
        for key in expectedKeys {
            #expect(decoded[key]?.isEmpty == false)
        }
    }

    /// bannerStringsScript が注入する各キーが viewer-main.js 側で `strings.<key>` として
    /// 読まれていることを検証する(タイポ時に英語文言へ静かに縮退するのを検知する)。
    @Test("bannerStrings の各キーが viewer-main.js で読み取られている")
    func bannerStringsKeysAreReadInJS() throws {
        let js = try String(contentsOf: resourceURL("viewer-main.js"), encoding: .utf8)
        let keys = try bridgeGlobalKeys(
            from: ViewerBridge.bannerStringsScript(), global: "window._mmdBannerStrings"
        )
        #expect(!keys.isEmpty)
        for key in keys {
            #expect(js.contains("strings.\(key)"), "banner キー '\(key)' が viewer-main.js で読まれていない")
        }
    }

    /// findStringsScript が注入する 8 キーが viewer-main.js 側で `strings.<key>` として
    /// 読まれていることを検証する。
    @Test("findStrings の各キーが viewer-main.js で読み取られている")
    func findStringsKeysAreReadInJS() throws {
        let js = try String(contentsOf: resourceURL("viewer-main.js"), encoding: .utf8)
        let keys = try bridgeGlobalKeys(
            from: ViewerBridge.findStringsScript(), global: "window._mmdFindStrings"
        )
        #expect(keys.count == 8)
        for key in keys {
            #expect(js.contains("strings.\(key)"), "find キー '\(key)' が viewer-main.js で読まれていない")
        }
    }

    /// FileType.jsValue が viewer-main.js の render() 分岐名と対応していることを検証する。
    /// markdown('md') は明示分岐を持たず else(既定)で処理されるため対象外。
    @Test("FileType.jsValue が render() の type 分岐に対応している")
    func fileTypeJSValuesMatchRenderBranches() throws {
        let js = try String(contentsOf: resourceURL("viewer-main.js"), encoding: .utf8)
        let fileTypes: [FileType] = [
            .mmd, .markdown, .svg, .html, .csv(delimiter: ","),
            .image(mimeType: "image/png"), .pdf, .code(language: "swift"),
        ]
        for fileType in fileTypes {
            let value = fileType.jsValue
            if value == "md" { continue }
            #expect(js.contains("type === '\(value)'"), "render() に type === '\(value)' 分岐がない")
        }
    }

    /// `global = { ... };` 形式のスクリプトから、注入される JSON オブジェクトのキー集合を取り出す。
    private func bridgeGlobalKeys(from script: String, global: String) throws -> [String] {
        let jsonPart = script
            .replacingOccurrences(of: "\(global) = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Array(decoded.keys)
    }

    /// ViewerBridge が参照する JS 関数・メッセージ名が viewer.html / viewer-main.js に
    /// 実在することをリポジトリ内のソースを読んで検証する(ブリッジ契約のドリフト検知)。
    /// インライン <script> は CSP の script-src から 'unsafe-inline' を除去する
    /// ために viewer-main.js へ外部化したため、
    /// 両ファイルの内容を連結して検証する(どちらに定義があっても検知できる)。
    @Test("ViewerBridge の関数名が viewer.html / viewer-main.js に定義されている")
    func bridgeFunctionsExistInViewerHTML() throws {
        let viewerHTML = try String(contentsOf: resourceURL("viewer.html"), encoding: .utf8)
        let viewerMainJS = try String(contentsOf: resourceURL("viewer-main.js"), encoding: .utf8)
        let html = viewerHTML + viewerMainJS

        #expect(html.contains("async function render(content, type, lang)"))
        #expect(html.contains("function _mmdZoomIn()"))
        #expect(html.contains("function _mmdZoomOut()"))
        #expect(html.contains("function _mmdZoomReset()"))
        #expect(html.contains("_MSG_ZOOM_CHANGED = '\(ViewerBridge.zoomChangedMessageName)'"))
        #expect(html.contains("_MSG_REFERENCE_ACTIVATED = '\(ViewerBridge.referenceActivatedMessageName)'"))
        #expect(html.contains("_MSG_FIND_OPTIONS_CHANGED = '\(ViewerBridge.findOptionsChangedMessageName)'"))
        #expect(html.contains("_MSG_SCROLL_POSITION_CHANGED = '\(ViewerBridge.scrollPositionChangedMessageName)'"))
        #expect(html.contains("_MSG_LOAD_MORE_LINES = '\(ViewerBridge.loadMoreLinesMessageName)'"))
        #expect(html.contains("function _mmdPostMessage(name, payload)"))
        #expect(html.contains("_mmdPostMessage(_MSG_ZOOM_CHANGED,"))
        #expect(html.contains("_mmdPostMessage(_MSG_REFERENCE_ACTIVATED,"))
        #expect(html.contains("_mmdPostMessage(_MSG_FIND_OPTIONS_CHANGED,"))
        #expect(html.contains("_mmdPostMessage(_MSG_SCROLL_POSITION_CHANGED,"))
        #expect(html.contains("_mmdPostMessage(_MSG_LOAD_MORE_LINES,"))
        #expect(html.contains("window._mmdInitialZoom"))
        #expect(html.contains("window._mmdSystemFontSize"))
        #expect(html.contains("function setViewMode(mode)"))
        #expect(html.contains("function _mmdInitZoom()"))
        #expect(html.contains("function setLineNumbers(show)"))
        #expect(html.contains("function _mmdSetTruncated(isTruncated, lineCount, failed)"))
        #expect(html.contains("function _mmdLoadMore()"))
        #expect(html.contains("window._mmdBannerStrings"))
        #expect(html.contains("window._mmdHostFeatures"))
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, 'loadMore')"))
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, 'spaceScroll')"))
        // referenceActivated/loadMoreLines の postMessage 発火は hostFeatures で
        // 多層防御する(Swift 側はハンドラ未登録、JS 側はここで呼び出し自体を抑止)。
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, 'referenceActivation')"))
        #expect(html.contains("function _mmdSetRestoreScroll(position)"))
        #expect(html.contains("function _mmdScrollTarget()"))
        #expect(html.contains("function _mmdOpenFind()"))
        #expect(html.contains("function _mmdCloseFind()"))
        #expect(html.contains("function _mmdFindRefresh(resetToFirst)"))
        #expect(html.contains("window._mmdInitialFindOptions"))
        #expect(html.contains("window._mmdFindStrings"))
        #expect(html.contains("function appendChunk(text, type, lang)"))
    }

    /// CSP の script-src に 'unsafe-inline' が残っていないことを検証する。
    /// アプリの JS は全て viewer.js / viewer-main.js 等の外部ファイルから読み込み、
    /// インライン <script> を使わない設計になったため、XSS がサニタイザ層を
    /// すり抜けても CSP がインライン script/イベントハンドラの実行をブロックできる。
    @Test("CSP の script-src から 'unsafe-inline' が削除されている")
    func cspScriptSrcHasNoUnsafeInline() throws {
        let html = try String(contentsOf: resourceURL("viewer.html"), encoding: .utf8)

        let cspLine = try #require(
            html.split(separator: "\n").first { $0.contains("Content-Security-Policy") }
        )
        let scriptSrcDirective = try #require(
            cspLine.split(separator: ";").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("script-src") }
        )
        #expect(!scriptSrcDirective.contains("unsafe-inline"))
        #expect(!html.contains("<script>\n"))
    }

    @Test("viewer.js の ZOOM_MIN / ZOOM_MAX が ZoomStore の範囲と一致する")
    func zoomRangeMatchesZoomStore() throws {
        let js = try String(contentsOf: resourceURL("viewer.js"), encoding: .utf8)

        #expect(js.contains("var ZOOM_MIN = \(ZoomStore.minZoom);"))
        #expect(js.contains("var ZOOM_MAX = \(ZoomStore.maxZoom);"))
    }

    @Test("viewer.js の ZOOM_STEP が ZoomStore.zoomStep と一致する")
    func zoomStepMatchesZoomStore() throws {
        let js = try String(contentsOf: resourceURL("viewer.js"), encoding: .utf8)

        #expect(js.contains("var ZOOM_STEP = \(ZoomStore.zoomStep);"))
    }

    @Test("viewer.js の ZOOM_DEFAULT が ZoomStore.defaultZoom と一致する")
    func zoomDefaultMatchesZoomStore() throws {
        let js = try String(contentsOf: resourceURL("viewer.js"), encoding: .utf8)

        #expect(js.contains("var ZOOM_DEFAULT = \(Int(ZoomStore.defaultZoom));"))
    }

    /// BefoldKit のリソースバンドルから、ビルド成果物に実際に含まれるリソース URL を返す。
    private func resourceURL(_ name: String) -> URL {
        let url = URL(fileURLWithPath: name)
        guard let resourceURL = Bundle.befoldKitResources.url(
            forResource: url.deletingPathExtension().lastPathComponent,
            withExtension: url.pathExtension
        ) else {
            fatalError("BefoldKit リソースが見つかりません: \(name)")
        }
        return resourceURL
    }
}
