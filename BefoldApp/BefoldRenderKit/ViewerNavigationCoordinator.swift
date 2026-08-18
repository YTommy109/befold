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
/// renderer は **weak** で持つ。「renderer がこの型を所有するので寿命は必ず renderer が
/// 長い」は、コールバックが同期で届く限りしか成り立たない。`async` な @objc delegate
/// メソッドはランタイムが Task を作って `self`(= このコーディネータ)だけを強参照するため、
/// サスペンド中に renderer だけが解放されうる。unowned のままだと再開時にトラップする
/// (ReferenceResolutionQueue の TASK-448 と同型)。
///
/// あわせて `decidePolicyFor` は **async 版を使わない**。completion-handler 版なら
/// サスペンドが無く、renderer が消える窓そのものが生まれない。ここへ delegate メソッドを
/// 足すときも同じ理由で completion-handler 版を選ぶこと。
@MainActor
final class ViewerNavigationCoordinator: NSObject, WKNavigationDelegate {
    private weak var renderer: ViewerRenderer?

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let renderer else { return }
        renderer.directHTML.applyPendingZoom(to: webView)
        renderer.pageZoom.applyIfReady(assumingReady: true)
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
    ///
    /// renderer が既に無ければ表示先が無いので `.cancel` を返す。
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let renderer else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(
            renderer.directHTML.decidePolicy(webView: webView, navigationAction: navigationAction)
        )
    }

    private func handleNavigationFailure(webView: WKWebView) {
        guard let renderer else { return }
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
