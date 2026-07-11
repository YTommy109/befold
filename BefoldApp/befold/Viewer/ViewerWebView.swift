import SwiftUI
import WebKit

/// WKWebView で Mermaid / Markdown コンテンツをレンダリングする NSViewRepresentable。
/// Coordinator パターンで WKNavigationDelegate を処理する。
struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    /// レンダリング対象のファイルパス。HTML ファイルは loadFileURL による直接ロードに使う。
    let filePath: URL?
    /// ソース表示中かどうか。true の間 HTML ファイルも viewer.html でレンダリングする。
    let isSourceMode: Bool
    /// ソース表示中に行番号を表示するかどうか。
    let showLineNumbers: Bool
    /// ロード時に JS へ注入するファイル毎の初期倍率。
    let initialZoom: Double
    /// JS 側で倍率が変わったときに呼ばれる。
    let onZoomChanged: @MainActor (Double) -> Void
    /// cmd+click でリンクやパス参照がアクティベートされたときに呼ばれる。
    /// パラメータ: href, isExternal, newWindow
    let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
    /// 検索バーの3トグル(大文字小文字区別・単語マッチ・正規表現)の永続化ストア。
    let findOptionsPreference: FindOptionsPreference
    /// AppKit 側（メニューアクション）へ WKWebView を公開するプロキシ。
    let webViewProxy: WebViewProxy

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if DEBUG
            // Web インスペクタを有効化する（公開 API がないため KVC を使用）。
            // 開発ビルドのみで有効にし、リリースビルドには含めない
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let zoomScript = WKUserScript(
            source: ViewerBridge.initialZoomScript(initialZoom),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(zoomScript)
        // Markdown 本文をシステム設定のテキストサイズに合わせる。
        // preferredFont(.body) はアクセシビリティのテキストサイズ変更に追従する(既定 13pt)。
        let fontSizeScript = WKUserScript(
            source: ViewerBridge.systemFontSizeScript(
                NSFont.preferredFont(forTextStyle: .body).pointSize
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(fontSizeScript)
        let findOptionsScript = WKUserScript(
            source: ViewerBridge.initialFindOptionsScript(
                ViewerBridge.FindOptions(
                    caseSensitive: findOptionsPreference.caseSensitive,
                    wholeWord: findOptionsPreference.wholeWord,
                    useRegex: findOptionsPreference.useRegex
                )
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findOptionsScript)
        let findStringsScript = WKUserScript(
            source: ViewerBridge.findStringsScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findStringsScript)
        config.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: ViewerBridge.findOptionsChangedMessageName
        )
        context.coordinator.findOptionsPreference = findOptionsPreference
        config.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: ViewerBridge.zoomChangedMessageName
        )
        context.coordinator.onZoomChanged = onZoomChanged
        config.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: ViewerBridge.referenceActivatedMessageName
        )
        context.coordinator.onOpenReference = onOpenReference

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // WKWebView の背景を透明にする（公開 API がないため KVC を使用）
        webView.setValue(false, forKey: "drawsBackground")
        // トラックパッドのピンチジェスチャーでズームできるようにする。
        // viewer.html 経由のコンテンツは既存の ctrl+wheel ハンドラ(viewer.html)で
        // 対応済みだが、.html ファイル直接ロード時はこの経路を通らないため必要。
        webView.allowsMagnification = true
        // WebKit標準の「2本指スワイプでページ履歴を戻る/進む」は本アプリの
        // ページ内履歴(loadFileURLのみ)とは無関係なため無効化し、
        // ViewerWindowController が二本指スワイプでファイル履歴を扱えるようにする。
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        context.coordinator.webViewProxy = webViewProxy
        webViewProxy.webView = webView

        Self.loadViewerHTML(into: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.onOpenReference = onOpenReference
        context.coordinator.findOptionsPreference = findOptionsPreference
        context.coordinator.initialPageZoom = initialZoom
        context.coordinator.updateContent(
            content,
            fileType: fileType,
            filePath: filePath,
            isSourceMode: isSourceMode,
            showLineNumbers: showLineNumbers
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// バンドル同梱の viewer.html を WebView へ読み込む。
    /// リソース名(`"viewer"` / `"html"`)の出現箇所をここに一本化する。
    static func loadViewerHTML(into webView: WKWebView) {
        guard let htmlURL = Bundle.l10n.url(forResource: "viewer", withExtension: "html") else { return }
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.zoomChangedMessageName)
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.referenceActivatedMessageName)
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.findOptionsChangedMessageName)
    }

    // MARK: - WeakScriptMessageHandler

    /// WKUserContentController はハンドラを強参照するため、Coordinator への参照を弱めて
    /// dismantleNSView の呼び出しに依存せずリークを防ぐプロキシ。
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

    // MARK: - Coordinator

    /// HTML ロード完了の検知と、コンテンツ差分に基づく再描画制御を行う。
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var webViewProxy: WebViewProxy?
        var onZoomChanged: (@MainActor (Double) -> Void)?
        var onOpenReference: (@MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void)?
        /// 検索バーの3トグルの永続化ストア。findOptionsChanged 受信時に書き戻す。
        var findOptionsPreference: FindOptionsPreference?
        /// updateNSView から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用に使う。
        var initialPageZoom: Double = 1.0
        /// HTML 直接ロード完了後に適用する pageZoom。適用後は nil に戻す。
        var pendingPageZoom: Double?
        private var isReady = false
        private var pendingUpdate: (() -> Void)?
        private var lastRenderedContent: String?
        private var lastRenderedFileType: FileType?
        private var lastShowLineNumbers: Bool?
        private var lastIsSourceMode: Bool?
        private var isDirectHTMLMode = false
        private var lastDirectHTMLPath: URL?

        // MARK: - WKScriptMessageHandler

        @MainActor
        func userContentController(
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
                      let isExternal = body["isExternal"] as? Bool,
                      let newWindow = body["newWindow"] as? Bool
            {
                onOpenReference?(href, isExternal, newWindow)
            } else if message.name == ViewerBridge.findOptionsChangedMessageName,
                      let body = message.body as? [String: Any],
                      let caseSensitive = body["caseSensitive"] as? Bool,
                      let wholeWord = body["wholeWord"] as? Bool,
                      let useRegex = body["useRegex"] as? Bool
            {
                findOptionsPreference?.caseSensitive = caseSensitive
                findOptionsPreference?.wholeWord = wholeWord
                findOptionsPreference?.useRegex = useRegex
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if isDirectHTMLMode, let zoom = pendingPageZoom {
                webView.pageZoom = zoom
                pendingPageZoom = nil
            }
            pendingUpdate?()
            pendingUpdate = nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleNavigationFailure(webView: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleNavigationFailure(webView: webView)
        }

        /// 直接 HTML モードを解除し、viewer.html へ復帰する。
        /// `isDirectHTMLMode` / `webViewProxy?.isDirectHTMLMode` / `lastDirectHTMLPath` /
        /// `lastRenderedContent` / `lastRenderedFileType` の 5 つの状態を必ずセットで
        /// リセットしてから viewer.html を再ロードする。一部だけ倒すと直接 HTML モードの
        /// 判定と再描画キャッシュの整合性が崩れるため、呼び出し側で個別にリセットしないこと。
        /// (`lastIsSourceMode` は viewer.html 再ロードに伴う JS 側 `_viewMode` の初期化と
        /// セットで `reloadViewerHTML` 側がリセットする)
        private func exitDirectHTMLMode(webView: WKWebView, completion: @escaping () -> Void) {
            isDirectHTMLMode = false
            webViewProxy?.isDirectHTMLMode = false
            lastDirectHTMLPath = nil
            lastRenderedContent = nil
            lastRenderedFileType = nil
            reloadViewerHTML(webView: webView, then: completion)
        }

        /// ナビゲーション失敗時に isReady のハングを防ぐ。直接ロード失敗なら viewer.html へ
        /// 安全にフォールバックする。
        private func handleNavigationFailure(webView: WKWebView) {
            pendingPageZoom = nil
            if isDirectHTMLMode {
                // 削除起因の失敗は onFileGone がウィンドウを閉じるため、ここでは
                // viewer.html へ戻すだけでよい
                exitDirectHTMLMode(webView: webView) {}
            } else {
                isReady = true
                pendingUpdate?()
                pendingUpdate = nil
            }
        }

        /// 初回の HTML ロード（loadFileURL）のみ許可し、それ以外のナビゲーションは全てキャンセルする。
        /// リンククリックやフォーム送信による意図しないページ遷移を防ぐ。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            switch navigationAction.navigationType {
            case .other:
                .allow
            default:
                .cancel
            }
        }

        func updateContent(
            _ content: String,
            fileType: FileType,
            filePath: URL?,
            isSourceMode: Bool,
            showLineNumbers: Bool
        ) {
            let doUpdate = { [weak self] in
                guard let self, let webView else { return }

                // HTML レンダリング表示: loadFileURL で直接ロード
                if fileType == .html, !isSourceMode, let filePath {
                    let pathChanged = filePath != lastDirectHTMLPath
                    let contentChanged = content != lastRenderedContent
                    guard !isDirectHTMLMode || pathChanged || contentChanged else { return }
                    // 初回ロード・ファイル切替では保存済みの per-file 倍率を使い、
                    // ライブリロード（同一ファイルの content 変更）では現在の倍率を維持する。
                    let isFirstLoadOrSwitch = !isDirectHTMLMode || pathChanged
                    pendingPageZoom = isFirstLoadOrSwitch ? initialPageZoom : webView.pageZoom
                    recordRendered(content: content, fileType: fileType)
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
                    exitDirectHTMLMode(webView: webView) {
                        self.applyRender(
                            webView: webView, content: content, fileType: fileType,
                            filePath: filePath, isSourceMode: isSourceMode,
                            showLineNumbers: showLineNumbers
                        )
                    }
                    recordRendered(content: content, fileType: fileType)
                    return
                }

                // content・fileType だけでなく isSourceMode の変化でも再描画する。
                // (例: notes.md → notes.txt のように内容が同じでも種別が変わる切替、
                // ソース/レンダリング表示の切替も同じ content から異なる文字列を描画し直す必要がある)
                let needsRender = content != lastRenderedContent
                    || fileType != lastRenderedFileType
                    || showLineNumbers != lastShowLineNumbers
                    || isSourceMode != lastIsSourceMode
                guard needsRender else { return }

                recordRendered(content: content, fileType: fileType)
                applyRender(
                    webView: webView, content: content, fileType: fileType,
                    filePath: filePath, isSourceMode: isSourceMode,
                    showLineNumbers: showLineNumbers
                )
            }

            if isReady {
                doUpdate()
            } else {
                pendingUpdate = doUpdate
            }
        }

        /// last* キャッシュとの差分を見て lineNumbers / viewMode を同期し、
        /// scrollKey 予告 + render を評価する。
        private func applyRender(
            webView: WKWebView, content: String, fileType: FileType,
            filePath: URL?, isSourceMode: Bool, showLineNumbers: Bool
        ) {
            if showLineNumbers != lastShowLineNumbers {
                webView.evaluateJavaScript(ViewerBridge.lineNumbersScript(showLineNumbers))
                lastShowLineNumbers = showLineNumbers
            }
            if isSourceMode != lastIsSourceMode {
                webView.evaluateJavaScript(
                    ViewerBridge.viewModeScript(isSourceMode ? .source : .rendered)
                )
                lastIsSourceMode = isSourceMode
            }
            guard let script = ViewerBridge.renderScript(
                content: Self.renderableContent(
                    content, fileType: fileType,
                    filePath: filePath, isSourceMode: isSourceMode
                ),
                fileType: fileType
            ) else { return }
            webView.evaluateJavaScript(ViewerBridge.scrollKeyScript(filePath: filePath))
            webView.evaluateJavaScript(script)
        }

        private func recordRendered(content: String, fileType: FileType) {
            lastRenderedContent = content
            lastRenderedFileType = fileType
        }

        /// render() に渡す直前のコンテンツ加工。markdown はローカル画像参照を
        /// data URI に差し替える(相対パスの解決基準として filePath が必要)。
        /// ソース表示中は原文をそのまま見せるため、埋め込みは行わない。
        nonisolated static func renderableContent(
            _ content: String, fileType: FileType, filePath: URL?, isSourceMode: Bool
        ) -> String {
            guard !isSourceMode, fileType == .markdown, let filePath else { return content }
            return MarkdownImageEmbedder.embedLocalImages(in: content, baseURL: filePath)
        }

        private func reloadViewerHTML(webView: WKWebView, then completion: @escaping () -> Void) {
            isReady = false
            // 再ロードで viewer.html の JS 状態(_showLineNumbers=false, _viewMode='rendered')が
            // 初期化されるため、Swift 側のキャッシュも破棄して次回更新時に
            // setLineNumbers / setViewMode を再注入させる。
            lastShowLineNumbers = nil
            lastIsSourceMode = nil
            // atDocumentStart の initialZoomScript はウィンドウ生成時の倍率で焼き付いているため、
            // 直接ロードから復帰した viewer.html に切替後の現在ファイルの保存倍率を適用し直す。
            let zoom = initialPageZoom
            pendingUpdate = {
                webView.evaluateJavaScript(ViewerBridge.applyZoomScript(zoom))
                completion()
            }
            // viewer.html（mermaid.js）は JS 必須のため、直接ロードで無効化した JS を再有効化する。
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            ViewerWebView.loadViewerHTML(into: webView)
        }
    }
}
