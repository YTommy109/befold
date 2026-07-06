import SwiftUI
import WebKit

/// WKWebView で Mermaid / Markdown コンテンツをレンダリングする NSViewRepresentable。
/// Coordinator パターンで WKNavigationDelegate を処理する。
struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    let isDeleted: Bool
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
        context.coordinator.updateContent(content, fileType: fileType, isDeleted: isDeleted)
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
        var onZoomChanged: (@MainActor (Double) -> Void)?
        var onOpenReference: (@MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void)?
        private var isReady = false
        private var pendingUpdate: (() -> Void)?
        private var lastRenderedContent: String?
        private var lastRenderedFileType: FileType?
        private var lastWasDeleted: Bool?

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

        func updateContent(_ content: String, fileType: FileType, isDeleted: Bool) {
            let doUpdate = { [weak self] in
                guard let self, let webView else { return }

                if isDeleted {
                    if lastWasDeleted != true {
                        webView.evaluateJavaScript(ViewerBridge.showDeletedBannerScript)
                        lastWasDeleted = true
                    }
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
    }
}
