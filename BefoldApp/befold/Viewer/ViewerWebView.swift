import BefoldKit
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
    /// ファイルの一部だけを読み込んでいる(段階読み込み中)かどうか。
    let isTruncated: Bool
    /// 現在表示している累積行数(段階読み込みのバナー表示に使う)。
    let lineCount: Int
    /// ロード時に JS へ注入するファイル毎の初期倍率。
    let initialZoom: Double
    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    let scrollPositionToRestore: Double
    /// JS 側でスクロール位置が変わったときに呼ばれる。(position, mode)
    let onScrollPositionChanged: @MainActor (_ position: Double, _ mode: ViewerBridge.ViewMode) -> Void
    /// JS 側で倍率が変わったときに呼ばれる。
    let onZoomChanged: @MainActor (Double) -> Void
    /// JS 側「続きを読み込む」押下時に呼ばれ、次チャンクと更新後の表示状態を非同期で返す。
    let onLoadMoreLines: @MainActor () async -> (chunk: String, isTruncated: Bool, lineCount: Int)?
    /// リンクやパス参照がアクティベートされたときに呼ばれる。
    /// パラメータ: href, newWindow
    let onOpenReference: @MainActor (_ href: String, _ newWindow: Bool) -> Void
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
            source: ViewerBridge.findStringsScript(bundle: .l10n),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findStringsScript)
        let bannerStringsScript = WKUserScript(
            source: ViewerBridge.bannerStringsScript(bundle: .l10n),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(bannerStringsScript)
        // JS → Swift の postMessage ハンドラをまとめて登録する(同一 delegate のため一括化)。
        for name in Self.messageHandlerNames {
            config.userContentController.add(
                WeakScriptMessageHandler(delegate: context.coordinator), name: name
            )
        }
        context.coordinator.findOptionsPreference = findOptionsPreference
        context.coordinator.onLoadMoreLines = onLoadMoreLines
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.onOpenReference = onOpenReference
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged

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
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged
        context.coordinator.onOpenReference = onOpenReference
        context.coordinator.onLoadMoreLines = onLoadMoreLines
        context.coordinator.findOptionsPreference = findOptionsPreference
        context.coordinator.initialPageZoom = initialZoom
        context.coordinator.scrollPositionToRestore = scrollPositionToRestore
        context.coordinator.updateContent(
            content,
            fileType: fileType,
            filePath: filePath,
            isSourceMode: isSourceMode,
            showLineNumbers: showLineNumbers,
            isTruncated: isTruncated,
            lineCount: lineCount
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// バンドル同梱の viewer.html を WebView へ読み込む。
    /// リソース名(`"viewer"` / `"html"`)の出現箇所をここに一本化する。
    static func loadViewerHTML(into webView: WKWebView, bundle: Bundle = .rendering) {
        guard let htmlURL = bundle.url(forResource: "viewer", withExtension: "html") else { return }
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }

    /// JS → Swift の postMessage ハンドラ名一覧。makeNSView での登録・dismantleNSView での
    /// 解除を一箇所から駆動する(新規メッセージ追加時はここに加えるだけでよい)。
    private static let messageHandlerNames = [
        ViewerBridge.findOptionsChangedMessageName,
        ViewerBridge.loadMoreLinesMessageName,
        ViewerBridge.loadAllLinesForSearchMessageName,
        ViewerBridge.zoomChangedMessageName,
        ViewerBridge.referenceActivatedMessageName,
        ViewerBridge.scrollPositionChangedMessageName,
    ]

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        for name in messageHandlerNames {
            nsView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
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
        var onScrollPositionChanged: (@MainActor (_ position: Double, _ mode: ViewerBridge.ViewMode) -> Void)?
        var onOpenReference: (@MainActor (_ href: String, _ newWindow: Bool) -> Void)?
        var onLoadMoreLines: (@MainActor () async -> (chunk: String, isTruncated: Bool, lineCount: Int)?)?
        /// 「続きを読み込む」の実行中フラグ。非同期読み込み中の再押下を無視し、
        /// 追記の交錯(順序の入れ替わり)を防ぐ。
        private var isLoadingMoreLines = false
        /// 検索バーの3トグルの永続化ストア。findOptionsChanged 受信時に書き戻す。
        var findOptionsPreference: FindOptionsPreference?
        /// updateNSView から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用に使う。
        var initialPageZoom: Double = 1.0
        /// render() 呼び出し前に JS へ注入するスクロール復元位置。
        var scrollPositionToRestore: Double = 0
        /// HTML 直接ロード完了後に適用する pageZoom。適用後は nil に戻す。
        var pendingPageZoom: Double?
        private var isReady = false
        private var pendingUpdate: (() -> Void)?
        private var lastRenderedContent: String?
        private var lastRenderedFileType: FileType?
        private var lastRenderedFilePath: URL?
        private var lastShowLineNumbers: Bool?
        private var lastIsSourceMode: Bool?
        private var lastIsTruncated: Bool?
        /// 最後に _mmdSetTruncated へ送った表示行数(非切り詰め時は 0 に正規化)。
        /// 切り詰め状態のまま行数だけが変わる再読込(3000 行 → 1000 行など)でも
        /// バナーを更新できるよう、isTruncated とセットで追跡する。
        private var lastTruncatedLineCount: Int?
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
            } else if message.name == ViewerBridge.loadAllLinesForSearchMessageName {
                handleLoadMoreLines(untilFullyLoaded: true)
            }
        }

        /// 次チャンクを非同期で取得し、キャッシュ更新と描画を行う。読み込み中の再入は
        /// isLoadingMoreLines で無視し、追記の交錯を防ぐ。untilFullyLoaded が true の場合、
        /// 検索バーを開いた時点で段階読み込み中だったときに残り全チャンクを読み終えるまで
        /// ループし、完了を JS 側(_mmdOnAllLinesLoaded)へ通知する。
        @MainActor
        private func handleLoadMoreLines(untilFullyLoaded: Bool = false) {
            guard !isLoadingMoreLines else { return }
            isLoadingMoreLines = true
            Task { @MainActor [self] in
                defer { isLoadingMoreLines = false }
                guard let webView else { return }
                while let result = await onLoadMoreLines?() {
                    // 連結代入は蓄積済み文字列全体をコピーする(呼び出しごとに O(n))ため、
                    // in-place の append で追記する。
                    if lastRenderedContent == nil { lastRenderedContent = "" }
                    lastRenderedContent?.append(result.chunk)
                    lastIsTruncated = result.isTruncated
                    lastTruncatedLineCount = result.isTruncated ? result.lineCount : 0

                    // ソース表示でも .code は render() がレンダリング表示と同一の描画をするため
                    // 追記で足りる。CSV のソース表示(レインボー表示)だけは描画が異なるため、
                    // 蓄積済みコンテンツ全体を再描画する。
                    if lastIsSourceMode == true, lastRenderedFileType?.csvDelimiter != nil,
                       let script = ViewerBridge.renderScript(
                           content: Self.renderableContent(
                               lastRenderedContent ?? "",
                               fileType: lastRenderedFileType ?? .code(language: "plaintext"),
                               filePath: lastRenderedFilePath, isSourceMode: true
                           ),
                           fileType: lastRenderedFileType ?? .code(language: "plaintext")
                       )
                    {
                        webView.evaluateJavaScript(script, completionHandler: nil)
                    } else if let script = ViewerBridge.appendChunkScript(
                        chunk: result.chunk,
                        fileType: lastRenderedFileType ?? .code(language: "plaintext")
                    ) {
                        webView.evaluateJavaScript(script, completionHandler: nil)
                    }
                    webView.evaluateJavaScript(
                        ViewerBridge.truncatedScript(result.isTruncated, lineCount: result.lineCount),
                        completionHandler: nil
                    )
                    if !untilFullyLoaded { break }
                }
                if untilFullyLoaded {
                    webView.evaluateJavaScript(ViewerBridge.allLinesLoadedScript, completionHandler: nil)
                }
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
        /// `lastRenderedContent` / `lastRenderedFileType` / `lastRenderedFilePath` の 6 つの
        /// 状態を必ずセットでリセットしてから viewer.html を再ロードする。一部だけ倒すと
        /// 直接 HTML モードの判定と再描画キャッシュの整合性が崩れるため、呼び出し側で
        /// 個別にリセットしないこと。
        /// (`lastIsSourceMode` は viewer.html 再ロードに伴う JS 側 `_viewMode` の初期化と
        /// セットで `reloadViewerHTML` 側がリセットする)
        private func exitDirectHTMLMode(webView: WKWebView, completion: @escaping () -> Void) {
            isDirectHTMLMode = false
            webViewProxy?.isDirectHTMLMode = false
            lastDirectHTMLPath = nil
            lastRenderedContent = nil
            lastRenderedFileType = nil
            lastRenderedFilePath = nil
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

        /// 初回の HTML ロード（loadFileURL）は常に許可する。viewer.html モードではそれ以外の
        /// ナビゲーションを全てキャンセルする(JS 側がリンクを処理する)。直接 HTML モードでは
        /// リンククリック(.linkActivated)のみ directHTMLLinkPolicy で分類して処理する。
        /// (実装は type_body_length 対策で下部の extension に分離)
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            decidePolicyForDirectHTMLAware(webView: webView, navigationAction: navigationAction)
        }

        func updateContent(
            _ content: String,
            fileType: FileType,
            filePath: URL?,
            isSourceMode: Bool,
            showLineNumbers: Bool,
            isTruncated: Bool,
            lineCount: Int
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
                    recordRendered(content: content, fileType: fileType, filePath: filePath)
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
                            truncation: (isTruncated, lineCount),
                            restoreFromPersistedPosition: restoreFromPersistedPosition
                        )
                    }
                    recordRendered(content: content, fileType: fileType, filePath: filePath)
                    return
                }

                // content・fileType だけでなく isSourceMode の変化でも再描画する。
                // (例: notes.md → notes.txt のように内容が同じでも種別が変わる切替、
                // ソース/レンダリング表示の切替も同じ content から異なる文字列を描画し直す必要がある)
                let needsRender = content != lastRenderedContent
                    || fileType != lastRenderedFileType
                    || showLineNumbers != lastShowLineNumbers
                    || isSourceMode != lastIsSourceMode
                    || truncationStateChanged(isTruncated: isTruncated, lineCount: lineCount)
                guard needsRender else { return }

                let restoreFromPersistedPosition = Self.isFileOrModeSwitch(
                    filePath: filePath, isSourceMode: isSourceMode,
                    lastRenderedFilePath: lastRenderedFilePath, lastIsSourceMode: lastIsSourceMode
                )
                recordRendered(content: content, fileType: fileType, filePath: filePath)
                applyRender(
                    webView: webView, content: content, fileType: fileType,
                    filePath: filePath, isSourceMode: isSourceMode,
                    showLineNumbers: showLineNumbers,
                    truncation: (isTruncated, lineCount),
                    restoreFromPersistedPosition: restoreFromPersistedPosition
                )
            }

            if isReady {
                doUpdate()
            } else {
                pendingUpdate = doUpdate
            }
        }
    }
}

// MARK: - Render helpers

extension ViewerWebView.Coordinator {
    /// last* キャッシュとの差分を見て lineNumbers / viewMode を同期し、
    /// scrollKey 予告 + render を評価する。
    /// - Parameter restoreFromPersistedPosition: `isFileOrModeSwitch` 参照。
    private func applyRender(
        webView: WKWebView, content: String, fileType: FileType,
        filePath: URL?, isSourceMode: Bool, showLineNumbers: Bool,
        truncation: (isTruncated: Bool, lineCount: Int),
        restoreFromPersistedPosition: Bool
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
        if truncationStateChanged(isTruncated: truncation.isTruncated, lineCount: truncation.lineCount) {
            webView.evaluateJavaScript(
                ViewerBridge.truncatedScript(truncation.isTruncated, lineCount: truncation.lineCount)
            )
            lastIsTruncated = truncation.isTruncated
            lastTruncatedLineCount = truncation.isTruncated ? truncation.lineCount : 0
        }
        guard let script = ViewerBridge.renderScript(
            content: Self.renderableContent(
                content, fileType: fileType,
                filePath: filePath, isSourceMode: isSourceMode
            ),
            fileType: fileType
        ) else { return }
        if restoreFromPersistedPosition {
            webView.evaluateJavaScript(ViewerBridge.restoreScrollPositionScript(scrollPositionToRestore))
        }
        webView.evaluateJavaScript(script)
    }

    /// _mmdSetTruncated の再送が必要か(切り詰め状態、または切り詰め中の表示行数が
    /// 変わったか)を判定する。行数は非切り詰め時 0 に正規化して比較する。
    private func truncationStateChanged(isTruncated: Bool, lineCount: Int) -> Bool {
        isTruncated != lastIsTruncated
            || (isTruncated ? lineCount : 0) != lastTruncatedLineCount
    }

    /// 今回の render() がファイル/モードの実際の切替かどうかを判定する。
    /// 切替時のみ永続化済みスクロール位置(最大 200ms 古い可能性がある)で復元し、
    /// 同一ファイル・同一モードでの再描画(ライブリロード・行番号トグル等)では
    /// ライブの現在スクロール位置を優先させる(JS 側フォールバック。applyRender 参照)。
    nonisolated static func isFileOrModeSwitch(
        filePath: URL?, isSourceMode: Bool,
        lastRenderedFilePath: URL?, lastIsSourceMode: Bool?
    ) -> Bool {
        filePath != lastRenderedFilePath || isSourceMode != lastIsSourceMode
    }

    private func recordRendered(content: String, fileType: FileType, filePath: URL?) {
        lastRenderedContent = content
        lastRenderedFileType = fileType
        lastRenderedFilePath = filePath
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
        lastIsTruncated = nil
        lastTruncatedLineCount = nil
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

// MARK: - Direct HTML link policy

extension ViewerWebView.Coordinator {
    /// decidePolicyFor の実装本体。type_body_length 対策で struct 外の extension に分離している。
    /// 初回の HTML ロード（loadFileURL）は常に許可する。viewer.html モードではそれ以外の
    /// ナビゲーションを全てキャンセルする(JS 側がリンクを処理する)。直接 HTML モードでは
    /// リンククリック(.linkActivated)のみ directHTMLLinkPolicy で分類して処理する。
    func decidePolicyForDirectHTMLAware(
        webView: WKWebView,
        navigationAction: WKNavigationAction
    ) -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .other {
            return .allow
        }

        guard isDirectHTMLMode else {
            return .cancel
        }

        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            return .cancel
        }

        let action = Self.directHTMLLinkPolicy(
            url: url,
            currentURL: webView.url,
            modifierFlags: navigationAction.modifierFlags
        )

        switch action {
        case .allowNativeNavigation:
            return .allow
        case let .openLocalFile(fileURL, newWindow):
            onOpenReference?(fileURL.path, newWindow)
            return .cancel
        case let .openExternal(externalURL):
            NSWorkspace.shared.open(externalURL)
            return .cancel
        case .ignore:
            return .cancel
        }
    }

    /// 直接 HTML モードでのリンククリックに対する挙動分類。
    enum DirectHTMLLinkAction: Equatable {
        case allowNativeNavigation
        case openLocalFile(url: URL, newWindow: Bool)
        case openExternal(url: URL)
        case ignore
    }

    /// クリックされたリンク URL を分類する純関数。
    /// 同一文書内フラグメントはネイティブのスクロールに任せ、それ以外のローカルファイルは
    /// フラグメントを除去した上で cmd 修飾の有無に応じて同一/新規ウィンドウを判断する。
    nonisolated static func directHTMLLinkPolicy(
        url: URL,
        currentURL: URL?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> DirectHTMLLinkAction {
        if let fragment = url.fragment, !fragment.isEmpty,
           let currentURL,
           url.deletingFragment() == currentURL.deletingFragment()
        {
            return .allowNativeNavigation
        }

        let scheme = url.scheme ?? ""
        if scheme == "http" || scheme == "https" {
            return .openExternal(url: url)
        }

        if url.isFileURL {
            let cleanURL = url.fragment != nil ? url.deletingFragment() : url
            let newWindow = modifierFlags.contains(.command)
            return .openLocalFile(url: cleanURL, newWindow: newWindow)
        }

        return .ignore
    }
}

private extension URL {
    /// フラグメント(`#...`)を除去した URL を返す。
    func deletingFragment() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}
