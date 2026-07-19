import BefoldKit
import WebKit

/// WKWebView の構成・viewer.html ロード・render() 評価を担う WKWebView ドライバ。
/// find/loadMore/リンク遷移などアプリ専用機能はフック注入・オプショナルにしてあり、
/// QuickLook 拡張(.appex)のような静的1回描画ホストではそれらを省いて利用できる。
@MainActor
public final class ViewerRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    public var webView: WKWebView?
    public var webViewProxy: WebViewProxy?
    public var onZoomChanged: (@MainActor (Double) -> Void)?
    public var onScrollPositionChanged: (@MainActor (_ position: Double, _ mode: ViewerBridge.ViewMode) -> Void)?
    public var onOpenReference: (@MainActor (_ href: String, _ newWindow: Bool) -> Void)?
    public var onLoadMoreLines: (@MainActor () async -> LoadMoreLinesResult?)?
    /// 「続きを読み込む」の実行中フラグ。非同期読み込み中の再押下を無視し、
    /// 追記の交錯(順序の入れ替わり)を防ぐ。
    var isLoadingMoreLines = false
    /// 検索バーの3トグルの永続化ストア。findOptionsChanged 受信時に書き戻す。
    /// QuickLook 拡張等、検索 UI を持たないホストでは nil のまま省略できる。
    public var findOptionsPreference: FindOptionsPreference?
    /// 直接 HTML モード・相対画像埋め込みの有効/無効フラグ。
    public var rendererFeatures: RendererFeatures = .allEnabled
    /// 呼び出し側から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用に使う。
    public var initialPageZoom: Double = 1.0
    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    public var scrollPositionToRestore: Double = 0
    /// HTML 直接ロード完了後に適用する pageZoom。適用後は nil に戻す。
    var pendingPageZoom: Double?
    var isReady = false
    var pendingUpdate: (() -> Void)?
    /// 直近に描画した content の世代番号。content 全文を保持せず整数比較で
    /// 変更検知することで、呼び出し側の content との重複バッファを避ける。
    var lastRenderedContentRevision: Int?
    var lastRenderedFileType: FileType?
    var lastRenderedFilePath: URL?
    var lastShowLineNumbers: Bool?
    var lastIsSourceMode: Bool?
    /// 最後に _mmdSetTruncated へ送った切り詰め状態と表示行数
    /// (再読込での行数だけの変化もバナー更新できるよう両方をセットで保持する)。
    var lastTruncation: TruncationState?
    var isDirectHTMLMode = false
    var lastDirectHTMLPath: URL?

    override public init() {}

    /// WKWebView を構成し、viewer.html をロードして返す。
    /// - Parameters:
    ///   - initialZoom: ロード前に JS へ注入する初期倍率。
    ///   - findOptionsPreference: 検索バー3トグルの永続化ストア。QuickLook 等では nil を渡す。
    public func makeWebView(initialZoom: Double, findOptionsPreference: FindOptionsPreference?) -> WKWebView {
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
        }
        return names
    }

    /// makeWebView で登録した postMessage ハンドラを解除する。
    public func dismantle(_ webView: WKWebView) {
        for name in Self.messageHandlerNames(for: rendererFeatures) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    // MARK: - WeakScriptMessageHandler

    /// WKUserContentController はハンドラを強参照するため、ViewerRenderer への参照を弱めて
    /// dismantle の呼び出しに依存せずリークを防ぐプロキシ。
    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        private weak var delegate: WKScriptMessageHandler?

        init(delegate: WKScriptMessageHandler) {
            self.delegate = delegate
        }

        @MainActor
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }

    // MARK: - WKScriptMessageHandler

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == ViewerBridge.zoomChangedMessageName,
           let zoom = (message.body as? NSNumber)?.doubleValue
        {
            onZoomChanged?(zoom)
        } else if message.name == ViewerBridge.referenceActivatedMessageName,
                  let body = message.body as? [String: Any],
                  let href = body["href"] as? String,
                  let newWindow = body["newWindow"] as? Bool
        {
            onOpenReference?(href, newWindow)
        } else if message.name == ViewerBridge.scrollPositionChangedMessageName,
                  let body = message.body as? [String: Any],
                  let position = (body["position"] as? NSNumber)?.doubleValue,
                  let modeString = body["mode"] as? String,
                  let mode = ViewerBridge.ViewMode(rawValue: modeString)
        {
            onScrollPositionChanged?(position, mode)
        } else if message.name == ViewerBridge.findOptionsChangedMessageName,
                  let body = message.body as? [String: Any],
                  let caseSensitive = body["caseSensitive"] as? Bool,
                  let wholeWord = body["wholeWord"] as? Bool,
                  let useRegex = body["useRegex"] as? Bool
        {
            findOptionsPreference?.caseSensitive = caseSensitive
            findOptionsPreference?.wholeWord = wholeWord
            findOptionsPreference?.useRegex = useRegex
        } else if message.name == ViewerBridge.loadMoreLinesMessageName {
            handleLoadMoreLines()
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
    /// `isDirectHTMLMode` / `webViewProxy?.isDirectHTMLMode` / `lastDirectHTMLPath` /
    /// `lastRenderedContentRevision` / `lastRenderedFileType` /
    /// `lastRenderedFilePath` の 6 つの状態を必ずセットでリセットしてから viewer.html を
    /// 再ロードする。一部だけ倒すと直接 HTML モードの判定と再描画キャッシュの整合性が
    /// 崩れるため、呼び出し側で個別にリセットしないこと。
    /// (`lastIsSourceMode` は viewer.html 再ロードに伴う JS 側 `_viewMode` の初期化と
    /// セットで `reloadViewerHTML` 側がリセットする)
    func exitDirectHTMLMode(webView: WKWebView, completion: @escaping () -> Void) {
        isDirectHTMLMode = false
        webViewProxy?.isDirectHTMLMode = false
        lastDirectHTMLPath = nil
        lastRenderedContentRevision = nil
        lastRenderedFileType = nil
        lastRenderedFilePath = nil
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

    public func updateContent(
        _ content: String,
        contentRevision: Int,
        fileType: FileType,
        filePath: URL?,
        isSourceMode: Bool,
        showLineNumbers: Bool,
        truncation: TruncationState
    ) {
        let doUpdate = { [weak self] in
            guard let self, let webView else { return }

            // HTML レンダリング表示: loadFileURL で直接ロード
            if Self.shouldEnterDirectHTMLMode(
                fileType: fileType, isSourceMode: isSourceMode,
                filePath: filePath, features: rendererFeatures
            ), let filePath {
                let pathChanged = filePath != lastDirectHTMLPath
                let contentChanged = contentRevision != lastRenderedContentRevision
                guard !isDirectHTMLMode || pathChanged || contentChanged else { return }
                // 初回ロード・ファイル切替では保存済みの per-file 倍率を使い、
                // ライブリロード（同一ファイルの content 変更）では現在の倍率を維持する。
                let isFirstLoadOrSwitch = !isDirectHTMLMode || pathChanged
                pendingPageZoom = isFirstLoadOrSwitch ? initialPageZoom : webView.pageZoom
                recordRendered(
                    contentRevision: contentRevision,
                    fileType: fileType, filePath: filePath
                )
                lastIsSourceMode = isSourceMode
                lastDirectHTMLPath = filePath
                isDirectHTMLMode = true
                webViewProxy?.isDirectHTMLMode = true
                isReady = false
                // 直接ロードする HTML 内の <script> 実行を無効化する（設計スコープ外）。
                webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = false
                webView.loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())
                return
            }

            // 直接 HTML モードから viewer.html モードへの復帰
            if isDirectHTMLMode {
                // この分岐に来る時点でファイルかモードが直接HTML状態と必ず異なるため
                // (同一なら上の直接HTMLロード分岐に吸収される)、常に切替として扱われる。
                let restoreFromPersistedPosition = Self.isFileOrModeSwitch(
                    filePath: filePath, isSourceMode: isSourceMode,
                    lastRenderedFilePath: lastRenderedFilePath, lastIsSourceMode: lastIsSourceMode
                )
                exitDirectHTMLMode(webView: webView) {
                    self.applyRender(
                        webView: webView, content: content, fileType: fileType,
                        filePath: filePath, isSourceMode: isSourceMode,
                        showLineNumbers: showLineNumbers,
                        truncation: truncation,
                        restoreFromPersistedPosition: restoreFromPersistedPosition
                    )
                }
                recordRendered(
                    contentRevision: contentRevision,
                    fileType: fileType, filePath: filePath
                )
                return
            }

            // content・fileType だけでなく isSourceMode の変化でも再描画する。
            // (例: notes.md → notes.txt のように内容が同じでも種別が変わる切替、
            // ソース/レンダリング表示の切替も同じ content から異なる文字列を描画し直す必要がある)
            let needsRender = contentRevision != lastRenderedContentRevision
                || fileType != lastRenderedFileType
                || showLineNumbers != lastShowLineNumbers
                || isSourceMode != lastIsSourceMode
                || truncation != lastTruncation
            guard needsRender else { return }

            let restoreFromPersistedPosition = Self.isFileOrModeSwitch(
                filePath: filePath, isSourceMode: isSourceMode,
                lastRenderedFilePath: lastRenderedFilePath, lastIsSourceMode: lastIsSourceMode
            )
            recordRendered(
                contentRevision: contentRevision,
                fileType: fileType, filePath: filePath
            )
            applyRender(
                webView: webView, content: content, fileType: fileType,
                filePath: filePath, isSourceMode: isSourceMode,
                showLineNumbers: showLineNumbers,
                truncation: truncation,
                restoreFromPersistedPosition: restoreFromPersistedPosition
            )
        }

        if isReady {
            doUpdate()
        } else {
            pendingUpdate = doUpdate
        }
    }

    /// _mmdSetTruncated へ送る切り詰め状態と表示行数のペア。非切り詰め時の
    /// 行数は 0 に正規化する(切り詰め有無だけが意味を持つ)。failed はチャンク
    /// 読込エラーによる打ち切りを示す(通常の再描画経路からは常に false)。
    public struct TruncationState: Equatable, Sendable {
        public let isTruncated: Bool
        public let lineCount: Int
        public let failed: Bool
        public init(isTruncated: Bool, lineCount: Int, failed: Bool) {
            self.isTruncated = isTruncated
            self.lineCount = isTruncated ? lineCount : 0
            self.failed = failed
        }
    }
}
