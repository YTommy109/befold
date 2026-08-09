@testable import befold
import BefoldKit
import Foundation
import Testing

/// Swift↔JS ブリッジ契約を、同梱 JS/HTML のソースを読んで検証するテスト群。
///
/// 関数名・メッセージ名・ペイロードキー・定数値は Swift 側と JS 側の双方に現れるため、
/// 片側だけ変更しても実行時まで気づけない。ここでソースを機械的に走査して突合し、
/// ドリフトをビルド時に落とす。ViewerBridge の文字列生成そのものの検証は
/// ViewerBridgeTests が担う。
@Suite
@MainActor // ZoomStore(@MainActor)の static 定数を参照するため
struct ViewerBridgeContractTests {
    // MARK: - 関数名・メッセージ名

    /// ViewerBridge が参照する JS 関数・メッセージ名が viewer.html / viewer-main.js に
    /// 実在することをリポジトリ内のソースを読んで検証する(ブリッジ契約のドリフト検知)。
    /// インライン <script> は CSP の script-src から 'unsafe-inline' を除去する
    /// ために viewer-main.js へ外部化したため、
    /// 両ファイルの内容を連結して検証する(どちらに定義があっても検知できる)。
    @Test("ViewerBridge の関数名が viewer.html / viewer-main.js に定義されている")
    func bridgeFunctionsExistInViewerHTML() throws {
        let viewerHTML = try String(contentsOf: Self.resourceURL("viewer.html"), encoding: .utf8)
        let viewerMainJS = try String(contentsOf: Self.resourceURL("viewer-main.js"), encoding: .utf8)
        let html = viewerHTML + viewerMainJS

        // 引数なし呼び出し(_mmd*())は ViewerBridge.PlainFunction が単一情報源なので、
        // 手書きの列挙ではなく allCases を反復して照合する(定数追加時の照合漏れを防ぐ)。
        for function in ViewerBridge.PlainFunction.allCases {
            #expect(
                html.contains(function.definitionToken),
                "JS 側に \(function.definitionToken) の定義がない"
            )
        }

        #expect(html.contains("async function render(content, type, lang)"))
        #expect(html.contains("_MSG_ZOOM_CHANGED = '\(ViewerBridge.zoomChangedMessageName)'"))
        #expect(html.contains("_MSG_REFERENCE_ACTIVATED = '\(ViewerBridge.referenceActivatedMessageName)'"))
        #expect(html.contains("_MSG_FIND_OPTIONS_CHANGED = '\(ViewerBridge.findOptionsChangedMessageName)'"))
        #expect(html.contains("_MSG_SCROLL_POSITION_CHANGED = '\(ViewerBridge.scrollPositionChangedMessageName)'"))
        #expect(html.contains("_MSG_LOAD_MORE_LINES = '\(ViewerBridge.loadMoreLinesMessageName)'"))
        #expect(html.contains("_MSG_RESOLVE_REFERENCES = '\(ViewerBridge.resolveReferencesMessageName)'"))
        // 表示時解決: JS が候補を集めて要求する側(_mmdResolveReferences)と、
        // Swift の応答を適用する側(applyResolvedReferencesScript が呼ぶ関数)の両方を確認する。
        #expect(html.contains("function _mmdResolveReferences()"))
        #expect(html.contains("function _mmdApplyResolvedReferences(map)"))
        #expect(html.contains("function _mmdPostMessage(name, payload)"))
        #expect(html.contains("_mmdPostMessage(_MSG_ZOOM_CHANGED,"))
        #expect(html.contains("window._mmdInitialZoom"))
        #expect(html.contains("window._mmdSystemFontSize"))
        #expect(html.contains("function setViewMode(mode)"))
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
        #expect(html.contains("function _mmdSetRenderDocPath(path)"))
        #expect(html.contains("function _mmdRenameDocPath(from, to)"))
        // _mmdCloseFind / _mmdLoadMore は Swift から呼ばない JS 内部専用の関数だが、
        // 検索バーの Esc・バナーのボタン配線が生きていることをここで確認する。
        #expect(html.contains("function _mmdCloseFind()"))
        #expect(html.contains("function _mmdFindRefresh(resetToFirst)"))
        #expect(html.contains("window._mmdInitialFindOptions"))
        #expect(html.contains("window._mmdFindStrings"))
        #expect(html.contains("function appendChunk(text, type, lang)"))
    }

    // MARK: - ペイロードキー

    /// JS 側の 1 つの postMessage 送信サイト。
    private struct PostSite {
        let messageName: String
        let payloadKeys: Set<String>
    }

    @Test("JS の postMessage ペイロードキーが ViewerBridge の宣言と一致する")
    func payloadKeysMatchDeclaration() throws {
        let sites = try Self.objectPayloadSites()
        #expect(!sites.isEmpty, "viewer-main.js からオブジェクト送信サイトを抽出できていない")

        for site in sites {
            let declared = ViewerBridge.payloadKeysByMessageName[site.messageName]
            #expect(
                declared != nil,
                "'\(site.messageName)' のペイロードキーが ViewerBridge に未宣言"
            )
            let mismatch = "'\(site.messageName)' のキーが不一致: "
                + "JS=\(site.payloadKeys.sorted()) Swift=\((declared ?? []).sorted())"
            #expect(declared == site.payloadKeys, "\(mismatch)")
        }
    }

    @Test("ViewerBridge が宣言する全メッセージが JS 側に送信サイトを持つ")
    func declaredMessagesHavePostSites() throws {
        let posted = try Set(Self.objectPayloadSites().map(\.messageName))

        for messageName in ViewerBridge.payloadKeysByMessageName.keys {
            #expect(
                posted.contains(messageName),
                "'\(messageName)' の _mmdPostMessage 送信サイトが viewer-main.js にない"
            )
        }
    }

    // MARK: - 注入グローバルのキー

    /// bannerStringsScript が注入する各キーが viewer-main.js 側で `strings.<key>` として
    /// 読まれていることを検証する(タイポ時に英語文言へ静かに縮退するのを検知する)。
    @Test("bannerStrings の各キーが viewer-main.js で読み取られている")
    func bannerStringsKeysAreReadInJS() throws {
        let source = try String(contentsOf: Self.resourceURL("viewer-main.js"), encoding: .utf8)
        let keys = try bridgeGlobalKeys(
            from: ViewerBridge.bannerStringsScript(), global: "window._mmdBannerStrings"
        )
        #expect(!keys.isEmpty)
        for key in keys {
            #expect(source.contains("strings.\(key)"), "banner キー '\(key)' が viewer-main.js で読まれていない")
        }
    }

    /// findStringsScript が注入する 8 キーが viewer-main.js 側で `strings.<key>` として
    /// 読まれていることを検証する。
    @Test("findStrings の各キーが viewer-main.js で読み取られている")
    func findStringsKeysAreReadInJS() throws {
        let source = try String(contentsOf: Self.resourceURL("viewer-main.js"), encoding: .utf8)
        let keys = try bridgeGlobalKeys(
            from: ViewerBridge.findStringsScript(), global: "window._mmdFindStrings"
        )
        #expect(keys.count == 8)
        for key in keys {
            #expect(source.contains("strings.\(key)"), "find キー '\(key)' が viewer-main.js で読まれていない")
        }
    }

    /// FileType.jsValue が viewer-main.js の render() 分岐名と対応していることを検証する。
    /// markdown('md') は明示分岐を持たず else(既定)で処理されるため対象外。
    @Test("FileType.jsValue が render() の type 分岐に対応している")
    func fileTypeJSValuesMatchRenderBranches() throws {
        let source = try String(contentsOf: Self.resourceURL("viewer-main.js"), encoding: .utf8)
        let fileTypes: [FileType] = [
            .mmd, .markdown, .svg, .html, .csv(delimiter: ","),
            .image(mimeType: "image/png"), .pdf, .code(language: "swift"),
        ]
        for fileType in fileTypes {
            let value = fileType.jsValue
            if value == "md" { continue }
            #expect(source.contains("type === '\(value)'"), "render() に type === '\(value)' 分岐がない")
        }
    }

    // MARK: - CSP・ズーム定数

    /// CSP の script-src に 'unsafe-inline' が残っていないことを検証する。
    /// アプリの JS は全て viewer.js / viewer-main.js 等の外部ファイルから読み込み、
    /// インライン <script> を使わない設計になったため、XSS がサニタイザ層を
    /// すり抜けても CSP がインライン script/イベントハンドラの実行をブロックできる。
    @Test("CSP の script-src から 'unsafe-inline' が削除されている")
    func cspScriptSrcHasNoUnsafeInline() throws {
        let html = try String(contentsOf: Self.resourceURL("viewer.html"), encoding: .utf8)

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
        let source = try String(contentsOf: Self.resourceURL("viewer.js"), encoding: .utf8)

        #expect(source.contains("var ZOOM_MIN = \(ZoomStore.minZoom);"))
        #expect(source.contains("var ZOOM_MAX = \(ZoomStore.maxZoom);"))
    }

    @Test("viewer.js の ZOOM_STEP が ZoomStore.zoomStep と一致する")
    func zoomStepMatchesZoomStore() throws {
        let source = try String(contentsOf: Self.resourceURL("viewer.js"), encoding: .utf8)

        #expect(source.contains("var ZOOM_STEP = \(ZoomStore.zoomStep);"))
    }

    @Test("viewer.js の ZOOM_DEFAULT が ZoomStore.defaultZoom と一致する")
    func zoomDefaultMatchesZoomStore() throws {
        let source = try String(contentsOf: Self.resourceURL("viewer.js"), encoding: .utf8)

        #expect(source.contains("var ZOOM_DEFAULT = \(Int(ZoomStore.defaultZoom));"))
    }

    // MARK: - ヘルパー

    /// `global = { ... };` 形式のスクリプトから、注入される JSON オブジェクトのキー集合を取り出す。
    private func bridgeGlobalKeys(from script: String, global: String) throws -> [String] {
        let jsonPart = script
            .replacingOccurrences(of: "\(global) = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Array(decoded.keys)
    }

    /// viewer-main.js から、オブジェクトリテラルをペイロードに渡す postMessage 送信サイトを
    /// すべて抽出する。zoomChanged のように裸の値を渡すサイトは対象外。
    private static func objectPayloadSites() throws -> [PostSite] {
        let source = try String(contentsOf: resourceURL("viewer-main.js"), encoding: .utf8)
        let messageNames = try messageNamesByJSConstant(in: source)

        // 例: _mmdPostMessage(_MSG_REFERENCE_ACTIVATED, { href: href, metaKey: e.metaKey, shiftKey: e.shiftKey });
        // ペイロードはネストしないオブジェクトリテラルのみを対象にする。
        let pattern = #"_mmdPostMessage\(\s*(_MSG_[A-Z_]+)\s*,\s*\{([^}]*)\}"#
        return try matches(of: pattern, in: source).map { groups in
            let constant = groups[1]
            guard let messageName = messageNames[constant] else {
                throw ContractError.unknownMessageConstant(constant)
            }
            return try PostSite(messageName: messageName, payloadKeys: objectKeys(in: groups[2]))
        }
    }

    /// `var _MSG_X = 'name';` 形式の宣言から JS 定数名 → メッセージ名の対応を作る
    /// (宣言子は同梱 JS の規約に合わせて var / const / let のいずれも受ける)。
    private static func messageNamesByJSConstant(in source: String) throws -> [String: String] {
        let pattern = #"(?:var|let|const)\s+(_MSG_[A-Z_]+)\s*=\s*'([A-Za-z]+)'"#
        let pairs = try matches(of: pattern, in: source).map { ($0[1], $0[2]) }
        #expect(!pairs.isEmpty, "viewer-main.js に _MSG_* 定数の宣言が見つからない")
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    /// オブジェクトリテラルの中身(`href: href, metaKey: e.metaKey, shiftKey: e.shiftKey`)からキー名を取り出す。
    private static func objectKeys(in body: String) throws -> Set<String> {
        let pattern = #"([A-Za-z_$][A-Za-z0-9_$]*)\s*:"#
        return try Set(matches(of: pattern, in: body).map { $0[1] })
    }

    /// 正規表現のマッチを、キャプチャグループの文字列配列(index 0 は全体)として返す。
    private static func matches(of pattern: String, in text: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0 ..< match.numberOfRanges).map { index in
                guard let groupRange = Range(match.range(at: index), in: text) else { return "" }
                return String(text[groupRange])
            }
        }
    }

    /// BefoldKit のリソースバンドルから、ビルド成果物に実際に含まれるリソース URL を返す。
    private static func resourceURL(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: name)
        guard let resourceURL = Bundle.befoldKitResources.url(
            forResource: url.deletingPathExtension().lastPathComponent,
            withExtension: url.pathExtension
        ) else {
            throw ContractError.missingResource(name)
        }
        return resourceURL
    }

    private enum ContractError: Error {
        case missingResource(String)
        case unknownMessageConstant(String)
    }
}
