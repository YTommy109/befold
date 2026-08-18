import BefoldKit
import WebKit

/// WKWebView のナビゲーション事象を受け取り、readiness ゲートと直接 HTML モードへ振り分ける。
///
/// ViewerRenderer から切り出してあるのは、JS からの postMessage を受ける
/// BridgeMessageRouter と同じ理由——framework の delegate 面という関心が
/// 「描画状態の管理」と独立しているため。受信・分類までがこの型の責務で、
/// 復帰の中身(倍率の当て直し・viewer.html の読み直し)は DirectHTMLModeController と
/// ViewerReadinessGate が持つ。ここへ判断ロジックを溜めないこと。
///
/// renderer はこの型を所有するため、寿命は必ず renderer が長い(unowned)。
/// `webView.navigationDelegate` は weak なので、renderer 消滅後のコールバックは無視される。
@MainActor
final class ViewerNavigationCoordinator: NSObject, WKNavigationDelegate {
    private unowned let renderer: ViewerRenderer

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        renderer.directHTML.applyPendingZoom(to: webView)
        renderer.applyInitialPageZoomIfReady(assumingReady: true)
        renderer.readiness.markReady()
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

    /// 初回の HTML ロード（loadFileURL）は常に許可する。viewer.html モードではそれ以外の
    /// ナビゲーションを全てキャンセルする(JS 側がリンクを処理する)。直接 HTML モードでは
    /// リンククリック(.linkActivated)のみ directHTMLLinkPolicy で分類して処理する。
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        renderer.directHTML.decidePolicy(webView: webView, navigationAction: navigationAction)
    }

    private func handleNavigationFailure(webView: WKWebView) {
        renderer.directHTML.discardPendingZoom()
        if renderer.directHTML.isActive {
            // 削除起因の失敗は呼び出し側がウィンドウを閉じる等の対応をするため、
            // ここでは viewer.html へ戻すだけでよい
            renderer.directHTML.exit(webView: webView) {}
        } else {
            renderer.readiness.flushPending()
        }
    }
}
