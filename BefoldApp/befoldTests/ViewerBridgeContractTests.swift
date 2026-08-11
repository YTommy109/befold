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

    /// ViewerBridge が参照する JS 関数・メッセージ名が viewer.html / viewer-bundle.js に
    /// 実在することをリポジトリ内のソースを読んで検証する(ブリッジ契約のドリフト検知)。
    /// インライン <script> は CSP の script-src から 'unsafe-inline' を除去する
    /// ために viewer-bundle.js へ外部化したため、
    /// 両ファイルの内容を連結して検証する(どちらに定義があっても検知できる)。
    @Test("ViewerBridge の関数名が viewer.html / viewer-bundle.js に定義されている")
    func bridgeFunctionsExistInViewerHTML() throws {
        let viewerHTML = try String(contentsOf: Self.resourceURL("viewer.html"), encoding: .utf8)
        let html = try viewerHTML + Self.viewerBundleSource()

        // 引数なし呼び出し(_mmd*())は ViewerBridge.PlainFunction が単一情報源なので、
        // 手書きの列挙ではなく allCases を反復して照合する(定数追加時の照合漏れを防ぐ)。
        for function in ViewerBridge.PlainFunction.allCases {
            #expect(
                html.contains(function.definitionToken),
                "JS 側に \(function.definitionToken) の定義がない"
            )
        }

        #expect(Self.definesFunction(html, "render", parameterCount: 3))
        #expect(html.contains("_MSG_ZOOM_CHANGED = \"\(ViewerBridge.zoomChangedMessageName)\""))
        #expect(html.contains("_MSG_REFERENCE_ACTIVATED = \"\(ViewerBridge.referenceActivatedMessageName)\""))
        #expect(html.contains("_MSG_FIND_OPTIONS_CHANGED = \"\(ViewerBridge.findOptionsChangedMessageName)\""))
        #expect(html.contains("_MSG_SCROLL_POSITION_CHANGED = \"\(ViewerBridge.scrollPositionChangedMessageName)\""))
        #expect(html.contains("_MSG_LOAD_MORE_LINES = \"\(ViewerBridge.loadMoreLinesMessageName)\""))
        #expect(html.contains("_MSG_RESOLVE_REFERENCES = \"\(ViewerBridge.resolveReferencesMessageName)\""))
        // 表示時解決: JS が候補を集めて要求する側(_mmdResolveReferences)と、
        // Swift の応答を適用する側(applyResolvedReferencesScript が呼ぶ関数)の両方を確認する。
        #expect(Self.definesFunction(html, "_mmdResolveReferences", parameterCount: 0))
        #expect(Self.definesFunction(html, "_mmdApplyResolvedReferences", parameterCount: 1))
        #expect(Self.definesFunction(html, "_mmdPostMessage", parameterCount: 2))
        #expect(html.contains("_mmdPostMessage(_MSG_ZOOM_CHANGED,"))
        #expect(html.contains("window._mmdInitialZoom"))
        #expect(html.contains("window._mmdSystemFontSize"))
        #expect(Self.definesFunction(html, "setViewMode", parameterCount: 1))
        #expect(Self.definesFunction(html, "setLineNumbers", parameterCount: 1))
        #expect(Self.definesFunction(html, "_mmdSetTruncated", parameterCount: 3))
        #expect(Self.definesFunction(html, "_mmdLoadMore", parameterCount: 0))
        #expect(html.contains("window._mmdBannerStrings"))
        #expect(html.contains("window._mmdHostFeatures"))
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, \"loadMore\")"))
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, \"spaceScroll\")"))
        // referenceActivated/loadMoreLines の postMessage 発火は hostFeatures で
        // 多層防御する(Swift 側はハンドラ未登録、JS 側はここで呼び出し自体を抑止)。
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, \"referenceActivation\")"))
        #expect(Self.definesFunction(html, "_mmdSetRestoreScroll", parameterCount: 1))
        #expect(Self.definesFunction(html, "_mmdSetRenderDocPath", parameterCount: 1))
        #expect(Self.definesFunction(html, "_mmdRenameDocPath", parameterCount: 2))
        // _mmdCloseFind / _mmdLoadMore は Swift から呼ばない JS 内部専用の関数だが、
        // 検索バーの Esc・バナーのボタン配線が生きていることをここで確認する。
        #expect(Self.definesFunction(html, "_mmdCloseFind", parameterCount: 0))
        #expect(Self.definesFunction(html, "_mmdFindRefresh", parameterCount: 1))
        #expect(html.contains("window._mmdInitialFindOptions"))
        #expect(html.contains("window._mmdFindStrings"))
        #expect(Self.definesFunction(html, "appendChunk", parameterCount: 3))
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
        #expect(!sites.isEmpty, "viewer-bundle.js からオブジェクト送信サイトを抽出できていない")

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
                "'\(messageName)' の _mmdPostMessage 送信サイトが viewer-bundle.js にない"
            )
        }
    }

    // MARK: - 注入グローバルのキー

    /// bannerStringsScript が注入する各キーが viewer-bundle.js 側で `strings.<key>` として
    /// 読まれていることを検証する(タイポ時に英語文言へ静かに縮退するのを検知する)。
    @Test("bannerStrings の各キーが viewer-bundle.js で読み取られている")
    func bannerStringsKeysAreReadInJS() throws {
        let source = try Self.viewerBundleSource()
        let keys = try bridgeGlobalKeys(
            from: ViewerBridge.bannerStringsScript(), global: "window._mmdBannerStrings"
        )
        #expect(!keys.isEmpty)
        for key in keys {
            #expect(source.contains("strings.\(key)"), "banner キー '\(key)' が viewer-bundle.js で読まれていない")
        }
    }

    /// findStringsScript が注入する 8 キーが viewer-bundle.js 側で `strings.<key>` として
    /// 読まれていることを検証する。
    @Test("findStrings の各キーが viewer-bundle.js で読み取られている")
    func findStringsKeysAreReadInJS() throws {
        let source = try Self.viewerBundleSource()
        let keys = try bridgeGlobalKeys(
            from: ViewerBridge.findStringsScript(), global: "window._mmdFindStrings"
        )
        #expect(keys.count == 8)
        for key in keys {
            #expect(source.contains("strings.\(key)"), "find キー '\(key)' が viewer-bundle.js で読まれていない")
        }
    }

    /// hostFeaturesScript が注入するキーが viewer-bundle.js 側で
    /// `isHostFeatureEnabled(window._mmdHostFeatures, "<key>")` として読まれていることを
    /// 検証する(TASK-432.4)。
    ///
    /// バナー・検索の文言と違い、ホスト機能フラグにはこの照合が無かった。キー名が
    /// 片側だけ変わると、JS は未指定のキーを読んで「有効」に縮退し(bridge.ts の
    /// isHostFeatureEnabled)、抑止が黙って効かなくなる。TypeScript 化で
    /// ViewerHostFeatures のキー名を JS 側にも手書きしたため、その手書きが
    /// Swift とずれたら落ちる形をここで用意する。
    ///
    /// 照合語に global 名を含めるのは、キー名だけで探すと別の注入(bannerStrings の
    /// "loadMore")に一致して誤って通るため。
    @Test("hostFeatures の各キーが viewer-bundle.js で読み取られている")
    func hostFeaturesKeysAreReadInJS() throws {
        let source = try Self.viewerBundleSource()
        let script = ViewerBridge.hostFeaturesScript(
            loadMore: true, spaceScroll: true, referenceActivation: true
        )
        let keys = try bridgeGlobalKeys(from: script, global: "window._mmdHostFeatures")
        #expect(keys.count == 3)
        for key in keys {
            #expect(
                source.contains("_mmdHostFeatures, \"\(key)\""),
                "hostFeatures キー '\(key)' が viewer-bundle.js で読まれていない"
            )
        }
    }

    /// FileType.jsValue が render() の分岐に対応していることを検証する。
    ///
    /// render() は type ではなく「描画形(shape)」で分岐する。type と表示モードから
    /// shape を決めるのは renderShape(viewer.js 由来)で、そこで写された名前が
    /// render() の分岐名になる(TASK-414)。この 2 段を両方見ないと、
    /// 種別を足したときに「shape へ写されたが描き手がいない」状態を見逃す。
    /// markdown('md' → 'markdown')は明示分岐を持たず else(既定)で処理されるため対象外。
    @Test("FileType.jsValue が render() の描画形分岐に対応している")
    func fileTypeJSValuesMatchRenderBranches() throws {
        // renderShape(viewer.js 由来)も render() の分岐(viewer-main.js 由来)も
        // 同じバンドルへまとまるため、1 つのソースを両方の照合に使う。
        let source = try Self.viewerBundleSource()
        // jsValue → renderShape がレンダリング表示で返す描画形。
        let shapeByJSValue = [
            "mmd": "mmd", "svg": "svg", "html": "html", "csv": "csv-table",
            "image": "image", "pdf": "pdf", "code": "code",
        ]
        let fileTypes: [FileType] = [
            .mmd, .markdown, .svg, .html, .csv(delimiter: ","),
            .image(mimeType: "image/png"), .pdf, .code(language: "swift"),
        ]
        for fileType in fileTypes {
            let value = fileType.jsValue
            if value == "md" { continue }
            let shape = try #require(shapeByJSValue[value], "jsValue '\(value)' の描画形が表に無い")
            #expect(source.contains("shape === \"\(shape)\""), "render() に shape === '\(shape)' 分岐がない")
        }
        // ソース表示だけが取る描画形も、描き手がいることを確かめる。
        #expect(source.contains("shape === \"csv-source\""), "render() に shape === 'csv-source' 分岐がない")
        #expect(source.contains("function renderShape("), "viewer-bundle.js に renderShape がない")
    }

    // MARK: - CSP・ズーム定数

    /// CSP の script-src に 'unsafe-inline' が残っていないことを検証する。
    /// アプリの JS は全て viewer-bundle.js 等の外部ファイルから読み込み、
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

    @Test("viewer-bundle.js の ZOOM_MIN / ZOOM_MAX が ZoomStore の範囲と一致する")
    func zoomRangeMatchesZoomStore() throws {
        let source = try Self.viewerBundleSource()

        #expect(try Self.jsNumber(named: "ZOOM_MIN", in: source) == ZoomStore.minZoom)
        #expect(try Self.jsNumber(named: "ZOOM_MAX", in: source) == ZoomStore.maxZoom)
    }

    @Test("viewer-bundle.js の ZOOM_STEP が ZoomStore.zoomStep と一致する")
    func zoomStepMatchesZoomStore() throws {
        let source = try Self.viewerBundleSource()

        #expect(try Self.jsNumber(named: "ZOOM_STEP", in: source) == ZoomStore.zoomStep)
    }

    @Test("viewer-bundle.js の ZOOM_DEFAULT が ZoomStore.defaultZoom と一致する")
    func zoomDefaultMatchesZoomStore() throws {
        let source = try Self.viewerBundleSource()

        #expect(try Self.jsNumber(named: "ZOOM_DEFAULT", in: source) == ZoomStore.defaultZoom)
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

    /// viewer-bundle.js から、オブジェクトリテラルをペイロードに渡す postMessage 送信サイトを
    /// すべて抽出する。zoomChanged のように裸の値を渡すサイトは対象外。
    private static func objectPayloadSites() throws -> [PostSite] {
        let source = try viewerBundleSource()
        let messageNames = try messageNamesByJSConstant(in: source)

        // 例: _mmdPostMessage(_MSG_REFERENCE_ACTIVATED, { href, metaKey: e.metaKey, shiftKey: e.shiftKey });
        // ペイロードはネストしないオブジェクトリテラルのみを対象にする。
        let pattern = #"_mmdPostMessage\(\s*(_MSG_[A-Z_]+)\s*,\s*\{([^}]*)\}"#
        return try matches(of: pattern, in: source).map { groups in
            let constant = groups[1]
            guard let messageName = messageNames[constant] else {
                throw ContractError.unknownMessageConstant(constant)
            }
            return PostSite(messageName: messageName, payloadKeys: objectKeys(in: groups[2]))
        }
    }

    /// `var _MSG_X = "name";` 形式の宣言から JS 定数名 → メッセージ名の対応を作る
    /// (宣言子は同梱 JS の規約に合わせて var / const / let のいずれも受ける)。
    private static func messageNamesByJSConstant(in source: String) throws -> [String: String] {
        let pattern = #"(?:var|let|const)\s+(_MSG_[A-Z_]+)\s*=\s*"([A-Za-z]+)""#
        let pairs = try matches(of: pattern, in: source).map { ($0[1], $0[2]) }
        #expect(!pairs.isEmpty, "viewer-bundle.js に _MSG_* 定数の宣言が見つからない")
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    /// オブジェクトリテラルの中身(`href, metaKey: e.metaKey, shiftKey: e.shiftKey`)からキー名を取り出す。
    ///
    /// esbuild は `href: href` を短縮記法 `href` へ畳むため、`key:` 形式だけを見る
    /// 正規表現では取りこぼす。`,` で区切り、`:` の前が識別子ならキーとして拾う
    /// (値の側の断片は識別子にならないので落ちる)。
    private static func objectKeys(in body: String) -> Set<String> {
        let identifier = try? NSRegularExpression(pattern: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#)
        let keys = body.split(separator: ",").compactMap { entry -> String? in
            let head = String(entry.split(separator: ":", maxSplits: 1)[0])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(head.startIndex..., in: head)
            guard identifier?.firstMatch(in: head, range: range) != nil else { return nil }
            return head
        }
        return Set(keys)
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

    /// `function <name>(...)` が指定した引数の個数で定義されているかを返す。
    ///
    /// 仮引数の**名前**では照合しない。ベンダー(markdown-it / highlight.js /
    /// DOMPurify)を同じ IIFE へバンドルするようになったため、esbuild が名前衝突を
    /// 避けて仮引数を改名する(`appendChunk(text, …)` → `appendChunk(text3, …)`)。
    /// ブリッジの契約は「関数名と引数の個数」であって、バンドル内部で付け替えられる
    /// 識別子ではない。名前で照合すると、無関係な依存追加でここが落ちる。
    private static func definesFunction(
        _ source: String, _ name: String, parameterCount: Int
    ) -> Bool {
        let pattern = #"function\s+"# + NSRegularExpression.escapedPattern(for: name)
            + #"\s*\(([^)]*)\)"#
        guard let found = try? matches(of: pattern, in: source) else { return false }
        return found.contains { match in
            let params = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let count = params.isEmpty ? 0 : params.split(separator: ",").count
            return count == parameterCount
        }
    }

    /// `var NAME = <数値>;` 形式の宣言から値を数値として取り出す。
    ///
    /// リテラルの表記を文字列で突き合わせない理由: esbuild は `2.0` を `2` へ
    /// 正規化するため、Swift 側の `\(ZoomStore.maxZoom)`("2.0")とは表記が食い違う。
    /// 表記に合わせて Int() を挟むといった小細工は、閾値の型や桁が変わるたびに
    /// 壊れる。ここで比較したいのは値なので、値として取り出して比べる。
    private static func jsNumber(named name: String, in source: String) throws -> Double {
        let pattern = #"(?:var|let|const)\s+"# + name + #"\s*=\s*(-?\d+(?:\.\d+)?)\s*;"#
        let found = try matches(of: pattern, in: source)
        let first = try #require(found.first, "JS 側に \(name) の数値宣言が見つからない")
        return try #require(Double(first[1]), "\(name) の値を数値として読めない: \(first[1])")
    }

    /// 検証対象の JS ソース。viewer-src/ のモジュールではなく、実際に .app へ
    /// 同梱される esbuild 成果物(viewer-bundle.js)を読む。ソースと成果物のズレは
    /// CI の `npm run check:viewer-bundle` が検出する。
    ///
    /// esbuild は文字列リテラルを二重引用符へ正規化し、`href: href` を短縮記法へ
    /// 畳むため、ここで照合するトークンはその形に合わせてある。
    private static func viewerBundleSource() throws -> String {
        try String(contentsOf: resourceURL("viewer-bundle.js"), encoding: .utf8)
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
