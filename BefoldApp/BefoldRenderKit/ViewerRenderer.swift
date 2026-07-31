import BefoldKit
import WebKit

/// ViewerRenderer が JS 側の出来事を通知する先。アプリ本体では ViewerWindowController が実装する。
///
/// 全メソッドに「何もしない」既定実装があるため、QuickLook 拡張のような
/// 静的 1 回描画ホストは必要なものだけを実装すればよい(delegate 自体を設定しなくてもよい)。
@MainActor
public protocol ViewerRendererDelegate: AnyObject {
    /// JS 側で表示倍率が変わった。
    func renderer(_ renderer: ViewerRenderer, didChangeZoom zoom: Double)
    /// JS 側でスクロール位置が変わった。
    func renderer(
        _ renderer: ViewerRenderer, didChangeScrollPosition position: Double, mode: ViewerBridge.ViewMode
    )
    /// リンクまたはパス参照がアクティベートされた。
    func renderer(_ renderer: ViewerRenderer, didActivateReference href: String, disposition: OpenDisposition)
    /// リンクまたはパス参照の上で ctrl+クリック(右クリック)された。
    func renderer(_ renderer: ViewerRenderer, didRequestContextMenuFor href: String)
    /// JS が検出したパス参照群の解決を要求した。
    /// 戻り値: 書かれたパス -> 解決済み絶対パス(実在するもののみ)。
    /// 解決は git subprocess を伴いうるため非同期。実装は MainActor をブロックせずに返すこと。
    func renderer(_ renderer: ViewerRenderer, resolveReferences paths: [String]) async -> [String: String]
    /// JS 側「続きを読み込む」が押された。次チャンクと更新後の表示状態を返す。
    func rendererDidRequestMoreLines(_ renderer: ViewerRenderer) async -> LoadMoreLinesResult?
}

public extension ViewerRendererDelegate {
    func renderer(_: ViewerRenderer, didChangeZoom _: Double) {}
    func renderer(_: ViewerRenderer, didChangeScrollPosition _: Double, mode _: ViewerBridge.ViewMode) {}
    func renderer(_: ViewerRenderer, didActivateReference _: String, disposition _: OpenDisposition) {}
    func renderer(_: ViewerRenderer, didRequestContextMenuFor _: String) {}
    func renderer(_: ViewerRenderer, resolveReferences _: [String]) async -> [String: String] {
        [:]
    }

    func rendererDidRequestMoreLines(_: ViewerRenderer) async -> LoadMoreLinesResult? {
        nil
    }
}

/// WKWebView の構成・viewer.html ロード・render() 評価を担う WKWebView ドライバ。
/// find/loadMore/リンク遷移などアプリ専用機能はフック注入・オプショナルにしてあり、
/// QuickLook 拡張(.appex)のような静的1回描画ホストではそれらを省いて利用できる。
@MainActor
public final class ViewerRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    public var webView: WKWebView?
    public var webViewProxy: WebViewProxy?
    /// JS 側で起きた出来事の通知先。アプリ本体では ViewerWindowController が実装する。
    /// 循環参照を避けるため weak。QuickLook 拡張のような静的 1 回描画ホストは
    /// 設定しないままでよい(全メソッドに既定実装があり、通知は捨てられる)。
    public weak var delegate: (any ViewerRendererDelegate)?
    /// 「続きを読み込む」の実行中フラグ。非同期読み込み中の再押下を無視し、
    /// 追記の交錯(順序の入れ替わり)を防ぐ。
    var isLoadingMoreLines = false
    /// 解決応答(applyResolvedReferences 評価)の直列チェーン。JS は応答を要求へ FIFO で
    /// 対応づけるため、解決が非同期になっても評価順が要求順とずれてはならない。
    /// 各要求は直前の要求の完了を待ってから解決・評価する。
    var resolveResponseChain: Task<Void, Never>?
    /// 検索バーの3トグルの永続化ストア。findOptionsChanged 受信時に書き戻す。
    /// QuickLook 拡張等、検索 UI を持たないホストでは nil のまま省略できる。
    public var findOptionsPreference: FindOptionsPreference?
    /// 直接 HTML モード・相対画像埋め込みの有効/無効フラグ。
    public var rendererFeatures: RendererFeatures = .allEnabled
    /// 呼び出し側から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用に使う。
    public var initialPageZoom: Double = 1.0
    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    public var scrollPositionToRestore: Double = 0
    /// loadOneShot が描画完了(mermaid 等の非同期描画を含む)を待つ上限。
    /// QuickLook のプレビュー生成をハングさせないための保険で、超過した場合は
    /// その時点の DOM のまま完了として返す。負荷の高いテスト環境など、
    /// ホスト側の事情で待ち時間を伸ばしたい場合に差し替える。
    public var oneShotRenderTimeout: Duration = .seconds(3)
    /// HTML 直接ロード完了後に適用する pageZoom。適用後は nil に戻す。
    var pendingPageZoom: Double?
    var isReady = false
    var pendingUpdate: (() -> Void)?
    /// 直近に描画した表示状態のミラー。呼び出し側 content の全文を保持せず、
    /// contentRevision の整数比較で再描画要否を判定することで重複バッファを避ける。
    /// viewer.html 再ロード時は 6 値を必ずセットで破棄する必要があるため、
    /// 個別フィールドではなく 1 つの struct にまとめ `reset()` で一括リセットする。
    struct RenderedStateMirror {
        /// 直近に描画した content の世代番号。
        var contentRevision: Int?
        var fileType: FileType?
        var filePath: URL?
        var showLineNumbers: Bool?
        var isSourceMode: Bool?
        /// 最後に _mmdSetTruncated へ送った切り詰め状態と表示行数
        /// (再読込での行数だけの変化もバナー更新できるよう両方をセットで保持する)。
        var truncation: TruncationState?

        /// viewer.html 再ロードで JS 側状態が初期化されるのに合わせて全ミラーを破棄する。
        mutating func reset() {
            self = RenderedStateMirror()
        }
    }

    var rendered = RenderedStateMirror()

    /// 段階読み込み(loadMoreLines)でステージされた次チャンク。実際の増分描画は
    /// @Observable 変更が駆動する updateContent(唯一の描画 sink)が消費して行う。
    /// revision は追記後の世代番号で、updateContent の contentRevision と一致した
    /// ときだけ増分描画する(不一致=別更新に追い越された場合は破棄し全文 render に倒す)。
    struct PendingAppend {
        let chunk: String
        let revision: Int
    }

    var pendingAppend: PendingAppend?
    var isDirectHTMLMode = false
    var lastDirectHTMLPath: URL?

    override public init() {}

    /// WKWebView を構成し、viewer.html をロードして返す。
    /// - Parameters:
    ///   - initialZoom: ロード前に JS へ注入する初期倍率。
    ///   - findOptionsPreference: 検索バー3トグルの永続化ストア。QuickLook 等では nil を渡す。
    ///   - codeFontFamily: ロード前に JS へ注入するソースビュー等幅フォントファミリー名。
    ///     nil はシステム既定(QuickLook 等では nil を渡す)。
    ///   - codeFontSizePoints: ロード前に JS へ注入するソースビューのコードフォントサイズ(pt)。
    ///     nil は未カスタマイズ(CSS 側の calc(本文*0.75) フォールバックへ委ね、
    ///     アクセシビリティ文字サイズに追従する)。
    public func makeWebView(
        initialZoom: Double, findOptionsPreference: FindOptionsPreference?,
        codeFontFamily: String? = nil, codeFontSizePoints: Double? = nil
    ) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if DEBUG
            // Web インスペクタを有効化する（公開 API がないため KVC を使用）。
            // 開発ビルドのみで有効にし、リリースビルドには含めない
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        // ロード前に注入する JS を一括登録する(全て atDocumentStart / メインフレーム限定)。
        // Markdown 本文をシステム設定のテキストサイズに合わせる際は preferredFont(.body) を使う
        // (アクセシビリティのテキストサイズ変更に追従、既定 13pt)。
        let userScriptSources = [
            ViewerBridge.initialZoomScript(initialZoom),
            ViewerBridge.systemFontSizeScript(
                NSFont.preferredFont(forTextStyle: .body).pointSize
            ),
            ViewerBridge.monoFontFamilyScript(codeFontFamily),
            ViewerBridge.codeFontSizeScript(codeFontSizePoints),
            ViewerBridge.initialFindOptionsScript(
                ViewerBridge.FindOptions(
                    caseSensitive: findOptionsPreference?.caseSensitive ?? false,
                    wholeWord: findOptionsPreference?.wholeWord ?? false,
                    useRegex: findOptionsPreference?.useRegex ?? false
                )
            ),
            ViewerBridge.findStringsScript(),
            ViewerBridge.bannerStringsScript(),
            ViewerBridge.hostFeaturesScript(
                loadMore: rendererFeatures.allowsInteractiveBridging,
                referenceActivation: rendererFeatures.allowsInteractiveBridging
            ),
        ]
        for source in userScriptSources {
            config.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        // JS → Swift の postMessage ハンドラをまとめて登録する(同一 delegate のため一括化)。
        for name in Self.messageHandlerNames(for: rendererFeatures) {
            config.userContentController.add(
                WeakScriptMessageHandler(delegate: self), name: name
            )
        }
        self.findOptionsPreference = findOptionsPreference
        initialPageZoom = initialZoom

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // WKWebView の背景を透明にする（公開 API がないため KVC を使用）
        webView.setValue(false, forKey: "drawsBackground")
        // トラックパッドのピンチジェスチャーでズームできるようにする。
        // viewer.html 経由のコンテンツは既存の ctrl+wheel ハンドラ(viewer.html)で
        // 対応済みだが、.html ファイル直接ロード時はこの経路を通らないため必要。
        webView.allowsMagnification = true
        // WebKit標準の「2本指スワイプでページ履歴を戻る/進む」は本アプリの
        // ページ内履歴(loadFileURLのみ)とは無関係なため無効化し、呼び出し側が
        // 二本指スワイプでファイル履歴を扱えるようにする。
        webView.allowsBackForwardNavigationGestures = false
        self.webView = webView

        Self.loadViewerHTML(into: webView)

        return webView
    }

    /// バンドル同梱の viewer.html を WebView へ読み込む。
    /// リソース名(`"viewer"` / `"html"`)の出現箇所をここに一本化する。
    /// 既定 bundle は BefoldRenderKit 自身のリソースバンドルではなく、viewer.html
    /// 本体を同梱する BefoldKit のリソースバンドル(`Bundle.main` 非依存)を指す。
    public nonisolated static func loadViewerHTML(into webView: WKWebView, bundle: Bundle = .befoldKitResources) {
        guard let htmlURL = bundle.url(forResource: "viewer", withExtension: "html") else { return }
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }

    /// JS → Swift の postMessage ハンドラ名一覧。makeWebView での登録・dismantle での
    /// 解除を一箇所から駆動する(新規メッセージ追加時はここに加えるだけでよい)。
    /// referenceActivated/loadMoreLines は features.allowsInteractiveBridging が false の
    /// (QuickLook 拡張等の静的1回描画ホストを想定した)場合、そもそも登録しない
    /// (多層防御: XSS が postMessage を直接呼んでもハンドラ未登録のため Swift 側に届かない)。
    public nonisolated static func messageHandlerNames(for features: RendererFeatures) -> [String] {
        var names = [
            ViewerBridge.findOptionsChangedMessageName,
            ViewerBridge.zoomChangedMessageName,
            ViewerBridge.scrollPositionChangedMessageName,
        ]
        if features.allowsInteractiveBridging {
            names.append(ViewerBridge.loadMoreLinesMessageName)
            names.append(ViewerBridge.referenceActivatedMessageName)
            names.append(ViewerBridge.resolveReferencesMessageName)
            names.append(ViewerBridge.referenceContextMenuMessageName)
        }
        return names
    }

    /// makeWebView で登録した postMessage ハンドラを解除する。
    public func dismantle(_ webView: WKWebView) {
        for name in Self.messageHandlerNames(for: rendererFeatures) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        if isDirectHTMLMode, let zoom = pendingPageZoom {
            webView.pageZoom = zoom
            pendingPageZoom = nil
        }
        pendingUpdate?()
        pendingUpdate = nil
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(webView: webView)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(webView: webView)
    }

    /// 初回の HTML ロード（loadFileURL）は常に許可する。viewer.html モードではそれ以外の
    /// ナビゲーションを全てキャンセルする(JS 側がリンクを処理する)。直接 HTML モードでは
    /// リンククリック(.linkActivated)のみ directHTMLLinkPolicy で分類して処理する。
    /// (実装は type_body_length 対策で ViewerRenderer+DirectHTMLLinkPolicy.swift に分離)
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        decidePolicyForDirectHTMLAware(webView: webView, navigationAction: navigationAction)
    }

    /// 直接 HTML モードを解除し、viewer.html へ復帰する。
    /// 直接 HTML モードの判定状態(`isDirectHTMLMode` / `webViewProxy?.isDirectHTMLMode` /
    /// `lastDirectHTMLPath`)と、`rendered` ミラー 6 値を必ずセットで破棄してから
    /// viewer.html を再ロードする。ミラーは `rendered.reset()` で一括リセットする
    /// (再ロードで JS 側状態 `_mmdViewOptions`(行番号 false / モード rendered)が
    /// 初期化されるため、Swift 側のミラーも全て破棄して次回更新時に再注入させる)。
    /// 一部だけ倒すと直接 HTML モードの判定と再描画キャッシュの整合性が崩れるため、
    /// 呼び出し側で個別にリセットしないこと。`pendingAppend` は `rendered` の一部ではないが、
    /// 直接 HTML モードへの切替(pendingAppend 消費前に return する分岐)を挟んで残留した
    /// 増分チャンクが復帰後に誤って古い内容へ適用されないよう、ここで併せて破棄する。
    func exitDirectHTMLMode(webView: WKWebView, completion: @escaping () -> Void) {
        isDirectHTMLMode = false
        webViewProxy?.isDirectHTMLMode = false
        lastDirectHTMLPath = nil
        rendered.reset()
        pendingAppend = nil
        reloadViewerHTML(webView: webView, then: completion)
    }

    /// ナビゲーション失敗時に isReady のハングを防ぐ。直接ロード失敗なら viewer.html へ
    /// 安全にフォールバックする。
    private func handleNavigationFailure(webView: WKWebView) {
        pendingPageZoom = nil
        if isDirectHTMLMode {
            // 削除起因の失敗は呼び出し側がウィンドウを閉じる等の対応をするため、
            // ここでは viewer.html へ戻すだけでよい
            exitDirectHTMLMode(webView: webView) {}
        } else {
            isReady = true
            pendingUpdate?()
            pendingUpdate = nil
        }
    }
}
