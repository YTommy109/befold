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

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if DEBUG
        // Web インスペクタを有効化する（公開 API がないため KVC を使用）。
        // 開発ビルドのみで有効にし、リリースビルドには含めない
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let zoomScript = WKUserScript(
            source: "window._mmdInitialZoom = \(initialZoom);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(zoomScript)
        config.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: "zoomChanged"
        )
        context.coordinator.onZoomChanged = onZoomChanged

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // WKWebView の背景を透明にする（公開 API がないため KVC を使用）
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        if let htmlURL = Bundle.main.url(forResource: "viewer", withExtension: "html") {
            let resourceDir = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.updateContent(content, fileType: fileType, isDeleted: isDeleted)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "zoomChanged")
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
        private var isReady = false
        private var pendingUpdate: (() -> Void)?
        private var lastRenderedContent: String?
        private var lastWasDeleted: Bool?

        // MARK: - WKScriptMessageHandler

        @MainActor
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "zoomChanged",
                  let zoom = (message.body as? NSNumber)?.doubleValue else { return }
            onZoomChanged?(zoom)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            pendingUpdate?()
            pendingUpdate = nil
        }

        func updateContent(_ content: String, fileType: FileType, isDeleted: Bool) {
            let doUpdate = { [weak self] in
                guard let self, let webView = self.webView else { return }

                if isDeleted {
                    if self.lastWasDeleted != true {
                        webView.evaluateJavaScript("showDeletedBanner()")
                        self.lastWasDeleted = true
                    }
                    return
                }

                guard content != self.lastRenderedContent || self.lastWasDeleted == true else {
                    return
                }

                self.lastWasDeleted = false
                self.lastRenderedContent = content

                // JSONEncoder でエスケープし、JS インジェクションを防ぐ
                guard let jsonData = try? JSONEncoder().encode(content),
                      let jsonString = String(data: jsonData, encoding: .utf8) else { return }
                let script = "render(\(jsonString), '\(fileType.jsValue)')"
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
