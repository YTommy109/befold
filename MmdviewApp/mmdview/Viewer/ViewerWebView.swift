import SwiftUI
import WebKit

struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    let isDeleted: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
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
