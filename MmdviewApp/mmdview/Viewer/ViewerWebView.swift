import SwiftUI
import WebKit

/// WKWebView で Mermaid / Markdown コンテンツをレンダリングする NSViewRepresentable。
/// Coordinator パターンで WKNavigationDelegate を処理する。
struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    let isDeleted: Bool

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

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
        context.coordinator.updateContent(content, fileType: fileType, isDeleted: isDeleted)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    /// HTML ロード完了の検知と、コンテンツ差分に基づく再描画制御を行う。
    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        private var isReady = false
        private var pendingUpdate: (() -> Void)?
        private var lastRenderedContent: String?
        private var lastWasDeleted: Bool?

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
                let js = "render(\(jsonString), '\(fileType.jsValue)')"
                webView.evaluateJavaScript(js)
            }

            if isReady {
                doUpdate()
            } else {
                pendingUpdate = doUpdate
            }
        }
    }
}
