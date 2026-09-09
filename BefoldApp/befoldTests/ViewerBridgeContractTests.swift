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
        let viewerHTML = try String(contentsOf: ViewerBridgeContractSupport.resourceURL("viewer.html"), encoding: .utf8)
        let html = try viewerHTML + ViewerBridgeContractSupport.viewerBundleSource()

        // 引数なし呼び出し(_mmd*())は ViewerBridge.PlainFunction が単一情報源なので、
        // 手書きの列挙ではなく allCases を反復して照合する(定数追加時の照合漏れを防ぐ)。
        for function in ViewerBridge.PlainFunction.allCases {
            #expect(
                html.contains(function.definitionToken),
                "JS 側に \(function.definitionToken) の定義がない"
            )
        }

        #expect(ViewerBridgeContractSupport.definesFunction(html, "render", parameterCount: 3))
        // 引数を取るため PlainFunction には載せられない入口。契約テストの網から
        // 外れるので、ここで明示的に定義の存在を確かめる(TASK-485.1)。
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdOpenJump", parameterCount: 1))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdApplyJumpAvailability", parameterCount: 1))
        #expect(html.contains("_MSG_ZOOM_CHANGED = \"\(ViewerBridgeMessage.zoomChanged.rawValue)\""))
        #expect(html.contains("_MSG_REFERENCE_ACTIVATED = \"\(ViewerBridgeMessage.referenceActivated.rawValue)\""))
        #expect(html.contains("_MSG_FIND_OPTIONS_CHANGED = \"\(ViewerBridgeMessage.findOptionsChanged.rawValue)\""))
        #expect(html.contains("_MSG_LOAD_MORE_LINES = \"\(ViewerBridgeMessage.loadMoreLines.rawValue)\""))
        #expect(html.contains("_MSG_RESOLVE_REFERENCES = \"\(ViewerBridgeMessage.resolveReferences.rawValue)\""))
        // 表示時解決: JS が候補を集めて要求する側(_mmdResolveReferences)と、
        // Swift の応答を適用する側(applyResolvedReferencesScript が呼ぶ関数)の両方を確認する。
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdResolveReferences", parameterCount: 0))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdApplyResolvedReferences", parameterCount: 1))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdPostMessage", parameterCount: 2))
        #expect(html.contains("_mmdPostMessage(_MSG_ZOOM_CHANGED,"))
        #expect(html.contains("window._mmdInitialZoom"))
        #expect(html.contains("window._mmdSystemFontSize"))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "setViewMode", parameterCount: 1))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "setLineNumbers", parameterCount: 1))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdSetTruncated", parameterCount: 3))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdLoadMore", parameterCount: 0))
        #expect(html.contains("window._mmdBannerStrings"))
        #expect(html.contains("window._mmdHostFeatures"))
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, \"loadMore\")"))
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, \"spaceScroll\")"))
        // referenceActivated/loadMoreLines の postMessage 発火は hostFeatures で
        // 多層防御する(Swift 側はハンドラ未登録、JS 側はここで呼び出し自体を抑止)。
        #expect(html.contains("isHostFeatureEnabled(window._mmdHostFeatures, \"referenceActivation\")"))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdSetRestoreScroll", parameterCount: 1))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdSetRenderDocPath", parameterCount: 1))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdRenameDocPath", parameterCount: 2))
        // _mmdCloseFind / _mmdLoadMore は Swift から呼ばない JS 内部専用の関数だが、
        // 検索バーの Esc・バナーのボタン配線が生きていることをここで確認する。
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdCloseFind", parameterCount: 0))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "_mmdFindRefresh", parameterCount: 1))
        #expect(html.contains("window._mmdInitialFindOptions"))
        #expect(html.contains("window._mmdFindStrings"))
        #expect(ViewerBridgeContractSupport.definesFunction(html, "appendChunk", parameterCount: 3))
    }

    // MARK: - ペイロードキー

    @Test("JS の postMessage ペイロードキーが ViewerBridge の宣言と一致する")
    func payloadKeysMatchDeclaration() throws {
        let sites = try ViewerBridgeContractSupport.objectPayloadSites()
        #expect(!sites.isEmpty, "viewer-bundle.js からオブジェクト送信サイトを抽出できていない")

        for site in sites {
            let declared = ViewerBridgeMessage.payloadKeysByMessageName[site.messageName]
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
        let posted = try Set(ViewerBridgeContractSupport.objectPayloadSites().map(\.messageName))

        for messageName in ViewerBridgeMessage.payloadKeysByMessageName.keys {
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
        let source = try ViewerBridgeContractSupport.viewerBundleSource()
        let keys = try ViewerBridgeContractSupport.bridgeGlobalKeys(
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
        let source = try ViewerBridgeContractSupport.viewerBundleSource()
        let keys = try ViewerBridgeContractSupport.bridgeGlobalKeys(
            from: ViewerFindBridge.findStringsScript(), global: "window._mmdFindStrings"
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
        let source = try ViewerBridgeContractSupport.viewerBundleSource()
        let script = ViewerBridge.hostFeaturesScript(
            loadMore: true, spaceScroll: true, referenceActivation: true
        )
        let keys = try ViewerBridgeContractSupport.bridgeGlobalKeys(from: script, global: "window._mmdHostFeatures")
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
        let source = try ViewerBridgeContractSupport.viewerBundleSource()
        // jsValue → renderShape がレンダリング表示で返す描画形。
        let shapeByJSValue = [
            "mmd": "mmd", "svg": "svg", "html": "html", "csv": "csv-table",
            "image": "image", "code": "code",
        ]
        // .pdf は含めない。PDF は viewer.html を通らず PDFView が描くため、
        // render() に描画形の分岐を持たない(ADR 0009)。
        let fileTypes: [FileType] = [
            .mmd, .markdown, .svg, .html, .csv(delimiter: ","),
            .image(mimeType: "image/png"), .code(language: "swift"),
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
        // PDF の描画形が復活していないこと。JS 側へ戻すと、Swift が PDFView へ
        // 送る面と viewer が描く面の 2 つが同じファイルを描く状態になる(ADR 0009)。
        #expect(!source.contains("shape === \"pdf\""), "render() に PDF の分岐が残っている")
        #expect(!source.contains("pdf-body"), "viewer 側に PDF 用のクラスが残っている")
    }

    // MARK: - CSP・ズーム定数

    /// CSP の script-src に 'unsafe-inline' が残っていないことを検証する。
    /// アプリの JS は全て viewer-bundle.js 等の外部ファイルから読み込み、
    /// インライン <script> を使わない設計になったため、XSS がサニタイザ層を
    /// すり抜けても CSP がインライン script/イベントハンドラの実行をブロックできる。
    @Test("CSP の script-src から 'unsafe-inline' が削除されている")
    func cspScriptSrcHasNoUnsafeInline() throws {
        let html = try String(contentsOf: ViewerBridgeContractSupport.resourceURL("viewer.html"), encoding: .utf8)

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
        let source = try ViewerBridgeContractSupport.viewerBundleSource()

        #expect(try ViewerBridgeContractSupport.jsNumber(named: "ZOOM_MIN", in: source) == ZoomStore.minZoom)
        #expect(try ViewerBridgeContractSupport.jsNumber(named: "ZOOM_MAX", in: source) == ZoomStore.maxZoom)
    }

    @Test("viewer-bundle.js の ZOOM_STEP が ZoomStore.zoomStep と一致する")
    func zoomStepMatchesZoomStore() throws {
        let source = try ViewerBridgeContractSupport.viewerBundleSource()

        #expect(try ViewerBridgeContractSupport.jsNumber(named: "ZOOM_STEP", in: source) == ZoomStore.zoomStep)
    }

    @Test("viewer-bundle.js の ZOOM_DEFAULT が ZoomStore.defaultZoom と一致する")
    func zoomDefaultMatchesZoomStore() throws {
        let source = try ViewerBridgeContractSupport.viewerBundleSource()

        #expect(try ViewerBridgeContractSupport.jsNumber(named: "ZOOM_DEFAULT", in: source) == ZoomStore.defaultZoom)
    }
}
