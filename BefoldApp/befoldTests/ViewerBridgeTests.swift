import BefoldKit
import Foundation
import Testing

/// ViewerBridge が組み立てるスクリプト文字列そのものの検証。
/// 同梱 JS/HTML との突合(契約のドリフト検知)は ViewerBridgeContractTests が担う。
@Suite
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
        #expect(ViewerBridge.systemFontSizeScript(13.0) == "window._mmdSystemFontSize = 13;")
    }

    @Test("非有限値は不正な JS リテラルを吐かず null へフォールバックする")
    func nonFiniteScalarsFallBackToNull() {
        #expect(ViewerBridge.initialZoomScript(.nan) == "window._mmdInitialZoom = null;")
        #expect(ViewerBridge.systemFontSizeScript(.infinity) == "window._mmdSystemFontSize = null;")
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

    @Test("ViewMode(isSourceMode:) が Bool をモードへ写す")
    func viewModeFromIsSourceMode() {
        #expect(ViewerBridge.ViewMode(isSourceMode: true) == .source)
        #expect(ViewerBridge.ViewMode(isSourceMode: false) == .rendered)
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

    @Test("フォントファミリーは JSON エスケープして注入する")
    func monoFontFamilyEscapes() {
        #expect(ViewerBridge.monoFontFamilyScript("SF Mono") == "window._mmdMonoFontFamily = \"SF Mono\";")
    }

    @Test("ファミリー nil のときは空文字を注入する")
    func monoFontFamilyNilIsEmpty() {
        #expect(ViewerBridge.monoFontFamilyScript(nil) == "window._mmdMonoFontFamily = \"\";")
    }

    @Test("引用符を含むフォント名でも壊れない（エスケープされる）")
    func monoFontFamilyWithQuote() {
        #expect(ViewerBridge.monoFontFamilyScript("a\"b") == "window._mmdMonoFontFamily = \"a\\\"b\";")
    }

    @Test("コードフォントサイズを pt 値として注入する")
    func codeFontSizeScriptEmitsPoints() {
        #expect(ViewerBridge.codeFontSizeScript(11) == "window._mmdCodeFontSize = 11;")
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

    /// PlainFunction から導出される呼び出しスクリプト定数の実値を固定する
    /// (JS 側の関数名と 1 文字単位で対応していることの回帰防止)。
    @Test("引数なし呼び出しスクリプト定数が固定の文字列である")
    func plainCallScriptsAreFixedStrings() {
        #expect(ViewerBridge.zoomInScript == "_mmdZoomIn()")
        #expect(ViewerBridge.zoomOutScript == "_mmdZoomOut()")
        #expect(ViewerBridge.zoomResetScript == "_mmdZoomReset()")
        #expect(ViewerBridge.openFindScript == "_mmdOpenFind()")
        #expect(ViewerBridge.findNextScript == "_mmdFindNextIfOpen()")
        #expect(ViewerBridge.findPrevScript == "_mmdFindPrevIfOpen()")
        #expect(
            ViewerBridge.currentScrollPositionScript
                == "(function() { var el = _mmdScrollTarget(); return el ? el.scrollTop : 0; })()"
        )
    }

    @Test("findOptionsChangedMessageName が固定値である")
    func findOptionsChangedMessageNameIsFixed() {
        #expect(ViewerBridge.findOptionsChangedMessageName == "findOptionsChanged")
    }

    @Test("initialFindOptionsScript がトグル値を埋め込む")
    func initialFindOptionsScriptEmbedsValues() throws {
        let options = ViewerBridge.FindOptions(caseSensitive: true, wholeWord: false, useRegex: true)
        let script = ViewerBridge.initialFindOptionsScript(options)

        #expect(script.hasPrefix("window._mmdInitialFindOptions = "))
        #expect(script.hasSuffix(";"))

        let jsonPart = script
            .replacingOccurrences(of: "window._mmdInitialFindOptions = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        #expect(decoded["caseSensitive"] == true)
        #expect(decoded["wholeWord"] == false)
        #expect(decoded["useRegex"] == true)
    }

    @Test("findStringsScript が window._mmdFindStrings への代入文を生成する")
    func findStringsScriptAssignsFindStringsGlobal() {
        let script = ViewerBridge.findStringsScript()

        #expect(script.hasPrefix("window._mmdFindStrings = "))
        #expect(script.hasSuffix(";"))
    }

    @Test("resolveReferencesMessageName が固定値である")
    func resolveReferencesMessageNameIsFixed() {
        #expect(ViewerBridge.resolveReferencesMessageName == "resolveReferences")
    }

    @Test("applyResolvedReferencesScript が _mmdApplyResolvedReferences 呼び出しを組み立てる")
    func applyResolvedReferencesScriptBuildsCallWithResolutions() throws {
        let script = ViewerBridge.applyResolvedReferencesScript(["docs/a.md": "/repo/docs/a.md"])

        #expect(script.hasPrefix("_mmdApplyResolvedReferences("))
        #expect(script.hasSuffix(")"))

        let jsonPart = String(script.dropFirst("_mmdApplyResolvedReferences(".count).dropLast())
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(decoded == ["docs/a.md": "/repo/docs/a.md"])
    }

    @Test("applyResolvedReferencesScript は空の解決結果でも空オブジェクトを生成する")
    func applyResolvedReferencesScriptHandlesEmptyResolutions() {
        #expect(ViewerBridge.applyResolvedReferencesScript([:]) == "_mmdApplyResolvedReferences({})")
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
}
