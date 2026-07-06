import SwiftUI
import WebKit

/// WKWebView で Mermaid / Markdown コンテンツをレンダリングする NSViewRepresentable。
/// Coordinator パターンで WKNavigationDelegate を処理する。
struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    let isDeleted: Bool
    /// レンダリング対象のファイルパス。HTML ファイルは loadFileURL による直接ロードに使う。
    let filePath: URL?
    /// ソース表示中かどうか。true の間 HTML ファイルも viewer.html でレンダリングする。
    let isSourceMode: Bool
    /// ロード時に JS へ注入するファイル毎の初期倍率。
    let initialZoom: Double
    /// JS 側で倍率が変わったときに呼ばれる。
    let onZoomChanged: @MainActor (Double) -> Void
    /// cmd+click でリンクやパス参照がアクティベートされたときに呼ばれる。
    /// パラメータ: href, isExternal, newWindow
    let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
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
        context.coordinator.webView = webView
        context.coordinator.webViewProxy = webViewProxy
        webViewProxy.webView = webView

        if let htmlURL = Bundle.l10n.url(forResource: "viewer", withExtension: "html") {
            let resourceDir = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.onOpenReference = onOpenReference
        context.coordinator.initialPageZoom = initialZoom
        context.coordinator.updateContent(
            content,
            fileType: fileType,
            isDeleted: isDeleted,
            filePath: filePath,
            isSourceMode: isSourceMode
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.zoomChangedMessageName)
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.referenceActivatedMessageName)
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
        /// updateNSView から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用に使う。
        var initialPageZoom: Double = 1.0
        /// HTML 直接ロード完了後に適用する pageZoom。適用後は nil に戻す。
        var pendingPageZoom: Double?
        private var isReady = false
        private var pendingUpdate: (() -> Void)?
        private var lastRenderedContent: String?
        private var lastRenderedFileType: FileType?
        private var lastWasDeleted: Bool?
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
            isDeleted: Bool,
            filePath: URL?,
            isSourceMode: Bool
        ) {
            let doUpdate = { [weak self] in
                guard let self, let webView else { return }

                if isDeleted {
                    // 削除状態は常に viewer.html モードで表示する
                    if isDirectHTMLMode {
                        isDirectHTMLMode = false
                        webViewProxy?.isDirectHTMLMode = false
                        lastDirectHTMLPath = nil
                        reloadViewerHTML(webView: webView) {
                            webView.evaluateJavaScript(ViewerBridge.showDeletedBannerScript)
                        }
                        return
                    }
                    if lastWasDeleted != true {
                        webView.evaluateJavaScript(ViewerBridge.showDeletedBannerScript)
                        lastWasDeleted = true
                    }
                    return
                }

                // HTML レンダリング表示: loadFileURL で直接ロード
                if fileType == .html, !isSourceMode, let filePath {
                    lastWasDeleted = false
                    let pathChanged = filePath != lastDirectHTMLPath
                    let contentChanged = content != lastRenderedContent
                    guard !isDirectHTMLMode || pathChanged || contentChanged else { return }
                    lastRenderedContent = content
                    lastRenderedFileType = fileType
                    lastDirectHTMLPath = filePath
                    isDirectHTMLMode = true
                    webViewProxy?.isDirectHTMLMode = true
                    isReady = false
                    pendingPageZoom = initialPageZoom
                    webView.loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())
                    return
                }

                // 直接 HTML モードから viewer.html モードへの復帰
                if isDirectHTMLMode {
                    isDirectHTMLMode = false
                    webViewProxy?.isDirectHTMLMode = false
                    lastDirectHTMLPath = nil
                    lastRenderedContent = nil
                    lastRenderedFileType = nil
                    reloadViewerHTML(webView: webView) {
                        // viewer.html ロード完了後にコンテンツを描画
                        guard let script = ViewerBridge.renderScript(content: content, fileType: fileType)
                        else { return }
                        webView.evaluateJavaScript(script)
                    }
                    lastWasDeleted = false
                    lastRenderedContent = content
                    lastRenderedFileType = fileType
                    return
                }

                // content だけでなく fileType の変化でも再描画する。
                // (例: notes.md → notes.txt のように内容が同じでも種別が変わる切替)
                let needsRender = content != lastRenderedContent
                    || fileType != lastRenderedFileType
                    || lastWasDeleted == true
                guard needsRender else { return }

                lastWasDeleted = false
                lastRenderedContent = content
                lastRenderedFileType = fileType

                // JSONEncoder でエスケープし、JS インジェクションを防ぐ
                guard let script = ViewerBridge.renderScript(content: content, fileType: fileType)
                else { return }
                webView.evaluateJavaScript(script)
            }

            if isReady {
                doUpdate()
            } else {
                pendingUpdate = doUpdate
            }
        }

        private func reloadViewerHTML(webView: WKWebView, then completion: @escaping () -> Void) {
            isReady = false
            pendingUpdate = completion
            if let htmlURL = Bundle.l10n.url(forResource: "viewer", withExtension: "html") {
                let resourceDir = htmlURL.deletingLastPathComponent()
                webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
            }
        }
    }
}
