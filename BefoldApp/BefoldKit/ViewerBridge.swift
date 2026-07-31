import Foundation

/// viewer.html 内の JS と Swift の間のブリッジ契約(関数名・メッセージ名・グローバル変数)を集約する。
/// ここの文字列を変更する場合は viewer.html 側の定義とあわせて変更すること
/// (整合性は ViewerBridgeTests がソースを読んで検証する)。
public enum ViewerBridge {
    /// JS 側でスクロール位置が変わったときに postMessage されるメッセージハンドラ名。
    /// payload: { position: Double, mode: String }
    public static let scrollPositionChangedMessageName = "scrollPositionChanged"

    /// JS 側で全体ズーム倍率が変わったときに postMessage されるメッセージハンドラ名。
    public static let zoomChangedMessageName = "zoomChanged"

    /// リンクやパス参照がクリックされたときに postMessage されるメッセージハンドラ名。
    /// 修飾キーの解釈は Swift 側(OpenDisposition)が行うため、JS は押下状態のみ送る。
    /// payload: { href: String, metaKey: Bool, shiftKey: Bool }
    public static let referenceActivatedMessageName = "referenceActivated"

    /// Swift から引数なしで呼び出す JS 関数。呼び出しスクリプト文字列と、JS 側の定義
    /// トークン(存在検証に使う)をこの 1 箇所から導出し、生リテラルの二重管理をなくす。
    public enum PlainFunction: String, CaseIterable, Sendable {
        case zoomIn = "_mmdZoomIn"
        case zoomOut = "_mmdZoomOut"
        case zoomReset = "_mmdZoomReset"
        /// 注入済みの _mmdInitialZoom を読んで即時反映する(applyZoomScript が使う)。
        case initZoom = "_mmdInitZoom"
        /// スクロール対象要素を返す(currentScrollPositionScript が使う)。
        case scrollTarget = "_mmdScrollTarget"
        case openFind = "_mmdOpenFind"
        case findNextIfOpen = "_mmdFindNextIfOpen"
        case findPrevIfOpen = "_mmdFindPrevIfOpen"
        /// 注入済みの等幅フォント設定を読んで CSS 変数へ反映する(applyCodeFontScript が使う)。
        case initCodeFont = "_mmdInitCodeFont"

        /// `_mmdZoomIn()` 形式の呼び出しスクリプト。
        public var callScript: String {
            "\(rawValue)()"
        }

        /// JS 側にこの関数が実在することを検証するための定義トークン。
        public var definitionToken: String {
            "function \(rawValue)()"
        }
    }

    public static let zoomInScript = PlainFunction.zoomIn.callScript
    public static let zoomOutScript = PlainFunction.zoomOut.callScript
    public static let zoomResetScript = PlainFunction.zoomReset.callScript

    /// ロード時にファイル毎の初期倍率を注入するスクリプト。
    public static func initialZoomScript(_ zoom: Double) -> String {
        "window._mmdInitialZoom = \(zoom);"
    }

    /// 表示中ファイルの切り替え時などに、保存済み倍率を注入し直して即時反映する
    /// スクリプト。viewer.html 側は _mmdInitZoom() が _mmdInitialZoom を読んで適用する。
    public static func applyZoomScript(_ zoom: Double) -> String {
        initialZoomScript(zoom) + " \(PlainFunction.initZoom.callScript);"
    }

    /// ロード時にシステム本文フォントサイズ(pt)を注入するスクリプト。
    /// viewer.html 側は _mmdInitFontSize() が読んで CSS 変数へ反映する。
    public static func systemFontSizeScript(_ size: Double) -> String {
        "window._mmdSystemFontSize = \(size);"
    }

    /// ロード時に等幅フォントファミリー名を注入するスクリプト。JSONEncoder で
    /// エスケープし、JS インジェクションを防ぐ。nil は空文字として注入する
    /// (viewer.html 側はこれをシステム既定へのフォールバックとして扱う)。
    public static func monoFontFamilyScript(_ family: String?) -> String {
        let encoded = (try? JSONEncoder().encode(family ?? "")).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return "window._mmdMonoFontFamily = \(encoded);"
    }

    /// ロード時にコードフォントサイズ(pt)を注入するスクリプト。nil は未カスタマイズを表す
    /// null を注入し、viewer.html 側で CSS 変数 --mmd-code-font-size を未設定のままにする
    /// (calc(本文*0.75) フォールバックへ委ね、アクセシビリティ文字サイズに追従する)。
    public static func codeFontSizeScript(_ points: Double?) -> String {
        "window._mmdCodeFontSize = \(points.map { String($0) } ?? "null");"
    }

    /// 表示中ファイルの切り替え時などに、等幅フォント設定を注入し直して即時反映する
    /// スクリプト。viewer.html 側は _mmdInitCodeFont() が注入値を読んで CSS 変数へ反映する。
    public static func applyCodeFontScript(family: String?, points: Double?) -> String {
        monoFontFamilyScript(family) + " " + codeFontSizeScript(points) + " "
            + PlainFunction.initCodeFont.callScript + ";"
    }

    /// render(content, type[, lang]) 呼び出しを組み立てる。
    /// content は JSONEncoder でエスケープし、JS インジェクションを防ぐ。
    /// 第 3 引数(lang)は FileType.renderLangArgument が返す固定文字列
    /// (.code の言語名 / .csv の区切り文字 / .image の MIME タイプ)のみで、
    /// ユーザー入力は混入しない。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    public static func renderScript(content: String, fileType: FileType) -> String? {
        contentCallScript(function: "render", content: content, fileType: fileType)
    }

    /// render() の完了を待つ `callAsyncJavaScript` 用の関数本体を組み立てる。
    /// render は async 関数で内部の mermaid 描画完了まで await 済みのため、
    /// 返る Promise の解決がそのまま描画完了になる(JS 側に完了通知の仕組みを
    /// 足す必要がない)。1 回描画ホスト(QuickLook 拡張)が使う。
    ///
    /// requestAnimationFrame でペイントまで待つことはしない。rAF はウィンドウに
    /// 載っていない WebView では発火しないため、待つと描画完了を検知できず
    /// 常にタイムアウトまで待たされる。DOM 更新の完了までを完了とみなす。
    public static func awaitRenderScript(content: String, fileType: FileType) -> String? {
        guard let call = renderScript(content: content, fileType: fileType) else { return nil }
        return "await \(call);"
    }

    /// fn(content, type[, lang]) 形式の JS 呼び出しを組み立てる共通実装。
    /// renderScript / appendChunkScript が委譲する。
    private static func contentCallScript(
        function: String, content: String, fileType: FileType
    ) -> String? {
        guard let jsonString = jsonLiteral(content) else { return nil }
        guard let lang = fileType.renderLangArgument else {
            return "\(function)(\(jsonString), '\(fileType.jsValue)')"
        }
        let escaped = lang == "\t" ? "\\t" : lang
        return "\(function)(\(jsonString), '\(fileType.jsValue)', '\(escaped)')"
    }

    /// Encodable 値を JSON リテラル文字列へ変換する(JS へ埋め込む際の
    /// 共通処理)。エンコードに失敗した場合は nil。
    private static func jsonLiteral(_ value: some Encodable) -> String? {
        guard let jsonData = try? JSONEncoder().encode(value) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }

    /// `global = <JSON>;` 形式のグローバル代入スクリプトを組み立てる。
    /// エンコードに失敗した場合は空オブジェクト `{}` へフォールバックする。
    private static func assignGlobalScript(_ global: String, _ value: some Encodable) -> String {
        "\(global) = \(jsonLiteral(value) ?? "{}");"
    }

    /// render() 呼び出しの直前に評価し、次に復元すべきスクロール位置(scrollTop)を
    /// JS 側へ注入するスクリプト。viewer.html 側は _mmdSetRestoreScroll() が受け取った
    /// 値を保持し、続く render() の末尾でその位置を復元する。
    /// position が非有限値(NaN/Infinity)の場合は不正な JS リテラルになるため 0 にフォールバックする。
    public static func restoreScrollPositionScript(_ position: Double) -> String {
        "_mmdSetRestoreScroll(\(position.isFinite ? position : 0))"
    }

    /// 現在のスクロール位置(scrollTop)を同期的に取得するスクリプト。ファイル/モード
    /// 切替直前に、退場側の正確な位置を明示的なキー(旧 URL・旧モード)へ保存するために使う
    /// (詳細は ViewerWindowController.saveScrollPositionBeforeTransition 参照)。
    public static let currentScrollPositionScript =
        "(function() { var el = \(PlainFunction.scrollTarget.callScript); " +
        "return el ? el.scrollTop : 0; })()"

    /// レンダリング表示とソース表示の切り替えモード。
    public enum ViewMode: String, Sendable {
        case rendered
        case source

        /// ソース表示中かどうかの Bool からモードを決める。アプリ側の状態(store.isSourceMode や
        /// 描画済みミラー)は Bool で持つため、その写像をここ 1 箇所に集約する。
        public init(isSourceMode: Bool) {
            self = isSourceMode ? .source : .rendered
        }
    }

    /// setViewMode(mode) 呼び出しを組み立てる。
    public static func viewModeScript(_ mode: ViewMode) -> String {
        "setViewMode('\(mode.rawValue)')"
    }

    /// setLineNumbers(show) 呼び出しを組み立てる。
    public static func lineNumbersScript(_ show: Bool) -> String {
        "setLineNumbers(\(show))"
    }

    /// _mmdSetTruncated(isTruncated, lineCount, failed) 呼び出しを組み立てる。
    /// failed はチャンク読込エラーで打ち切られたことを示す。true のとき、viewer.html は
    /// バナーを「続きを読み込む」ではなく「読込エラー」表示に切り替える。
    public static func truncatedScript(_ isTruncated: Bool, lineCount: Int, failed: Bool) -> String {
        "_mmdSetTruncated(\(isTruncated), \(lineCount), \(failed))"
    }

    /// JS 側「続きを読み込む」ボタン押下時に postMessage されるメッセージハンドラ名。
    public static let loadMoreLinesMessageName = "loadMoreLines"

    /// JS 側が検出したパス参照の解決を要求するときに postMessage されるメッセージハンドラ名。
    /// payload: { paths: [String] }
    public static let resolveReferencesMessageName = "resolveReferences"

    /// 解決結果(書かれたパス -> 解決済み絶対パス。未解決は含めない)を JS へ適用する
    /// スクリプトを組み立てる。viewer.html 側は _mmdApplyResolvedReferences() が受け取り、
    /// 収録されたパスだけをリンク化する。
    public static func applyResolvedReferencesScript(_ resolutions: [String: String]) -> String {
        "_mmdApplyResolvedReferences(\(jsonLiteral(resolutions) ?? "{}"))"
    }

    /// ロード時にホスト機能フラグを JS 側へ注入するスクリプト。
    /// viewer.html 側は window._mmdHostFeatures(未注入時は全機能有効扱い)を読み、
    /// Load More ボタンの表示可否・Space キーでのページスクロール可否・リンク/パス参照
    /// クリック時の referenceActivated postMessage 可否を切り替える。
    /// アプリ本体は全機能をフルサポートするためデフォルトは true。
    public static func hostFeaturesScript(
        loadMore: Bool = true, spaceScroll: Bool = true, referenceActivation: Bool = true
    ) -> String {
        let features: [String: Bool] = [
            "loadMore": loadMore,
            "spaceScroll": spaceScroll,
            "referenceActivation": referenceActivation,
        ]
        return assignGlobalScript("window._mmdHostFeatures", features)
    }

    /// appendChunk(content, type[, lang]) 呼び出しを組み立てる。
    /// content は JSONEncoder でエスケープし、JS インジェクションを防ぐ。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    public static func appendChunkScript(chunk: String, fileType: FileType) -> String? {
        contentCallScript(function: "appendChunk", content: chunk, fileType: fileType)
    }

    /// ロード時にバナーのローカライズ済み文字列を JS 側へ注入するスクリプト。
    /// viewer.html 側は _mmdSetTruncated() が window._mmdBannerStrings を読んで表示する。
    public static func bannerStringsScript(bundle: Bundle = .befoldKitResources) -> String {
        let strings: [String: String] = [
            "showing": String(localized: "banner.showing", bundle: bundle),
            "loadMore": String(localized: "banner.loadMore", bundle: bundle),
            "loadError": String(localized: "banner.loadError", bundle: bundle),
        ]
        return assignGlobalScript("window._mmdBannerStrings", strings)
    }

    /// 検索バーを開く(未オープンなら表示してフォーカス)スクリプト。
    public static let openFindScript = PlainFunction.openFind.callScript

    /// 次のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    public static let findNextScript = PlainFunction.findNextIfOpen.callScript

    /// 前のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    public static let findPrevScript = PlainFunction.findPrevIfOpen.callScript

    /// JS 側で検索トグル(大文字小文字区別・単語マッチ・正規表現)が変わったときに
    /// postMessage されるメッセージハンドラ名。
    public static let findOptionsChangedMessageName = "findOptionsChanged"

    /// 検索の3トグルの状態。
    public struct FindOptions: Equatable {
        public var caseSensitive: Bool
        public var wholeWord: Bool
        public var useRegex: Bool

        public init(caseSensitive: Bool, wholeWord: Bool, useRegex: Bool) {
            self.caseSensitive = caseSensitive
            self.wholeWord = wholeWord
            self.useRegex = useRegex
        }
    }

    /// ロード時に検索トグルの保存済み状態を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdInitialFindOptions を読んで適用する。
    public static func initialFindOptionsScript(_ options: FindOptions) -> String {
        "window._mmdInitialFindOptions = { caseSensitive: \(options.caseSensitive), " +
            "wholeWord: \(options.wholeWord), useRegex: \(options.useRegex) };"
    }

    /// ロード時に検索バーのローカライズ済み文字列を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdFindStrings を読んで各要素に適用する。
    /// JSONEncoder でエスケープし、ローカライズ済み文字列に引用符等が含まれても
    /// JS オブジェクトリテラルを壊さないようにする。
    public static func findStringsScript(bundle: Bundle = .befoldKitResources) -> String {
        let strings: [String: String] = [
            "placeholder": String(localized: "viewer.find.placeholder", bundle: bundle),
            "previous": String(localized: "viewer.find.previous", bundle: bundle),
            "next": String(localized: "viewer.find.next", bundle: bundle),
            "matchCase": String(localized: "viewer.find.matchCase", bundle: bundle),
            "matchWholeWord": String(localized: "viewer.find.matchWholeWord", bundle: bundle),
            "useRegularExpression": String(localized: "viewer.find.useRegularExpression", bundle: bundle),
            "close": String(localized: "viewer.find.close", bundle: bundle),
            "withinDisplayedRange": String(localized: "viewer.find.withinDisplayedRange", bundle: bundle),
        ]
        return assignGlobalScript("window._mmdFindStrings", strings)
    }

    // MARK: - ペイロードキー(JS → Swift)

    /// postMessage のペイロードオブジェクトのキー。Swift の読み取り側(ViewerRenderer)と
    /// JS の送信側(viewer-main.js)で同じ名前を使う必要があるため、ここを単一情報源にする
    /// (JS 側との突合は ViewerBridgePayloadContractTests がソースを読んで検証する)。
    public enum PayloadKey {
        /// referenceActivated のキー。
        public enum ReferenceActivated: String, CaseIterable, Sendable {
            case href
            case metaKey
            case shiftKey
        }

        /// scrollPositionChanged のキー。
        public enum ScrollPositionChanged: String, CaseIterable, Sendable {
            case position
            case mode
        }

        /// findOptionsChanged のキー。
        public enum FindOptionsChanged: String, CaseIterable, Sendable {
            case caseSensitive
            case wholeWord
            case useRegex
        }

        /// resolveReferences のキー。
        public enum ResolveReferences: String, CaseIterable, Sendable {
            case paths
        }
    }

    /// メッセージ名 → JS がオブジェクトとして送るペイロードのキー集合。
    /// zoomChanged は裸の数値を送るためキーを持たず、この表には登録しない。
    /// 契約テストは JS 側の全 postMessage 呼び出しを走査してこの表と突合するため、
    /// オブジェクトを送るメッセージを JS 側に追加してここへ登録しないとテストが失敗する。
    public static let payloadKeysByMessageName: [String: Set<String>] = [
        referenceActivatedMessageName: Set(PayloadKey.ReferenceActivated.allCases.map(\.rawValue)),
        scrollPositionChangedMessageName: Set(PayloadKey.ScrollPositionChanged.allCases.map(\.rawValue)),
        findOptionsChangedMessageName: Set(PayloadKey.FindOptionsChanged.allCases.map(\.rawValue)),
        loadMoreLinesMessageName: [],
        resolveReferencesMessageName: Set(PayloadKey.ResolveReferences.allCases.map(\.rawValue)),
    ]
}
