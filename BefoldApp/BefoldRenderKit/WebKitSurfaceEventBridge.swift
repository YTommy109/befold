import WebKit

/// WebKit のコールバックを、WebKit を知らない受け口（`SurfaceNavigationObserver` /
/// `SurfaceBridgeMessageObserver`）へ翻訳する唯一の場所。
///
/// **ここが WebKit のデリゲート準拠を引き受ける。** 上の層
/// （`ViewerNavigationCoordinator` / `BridgeMessageRouter`）は WKWebView も
/// WKScriptMessage も知らない。翻訳だけを行い、判断は一切持たないこと——
/// ここに条件が増えると、実装を差し替えたときに落ちる振る舞いがここに溜まる。
///
/// `decidePolicyFor` は **completion-handler 版を使う**。async 版だとサスペンド中に
/// 観測者だけが解放されうる窓が生まれる（`ViewerNavigationCoordinator` の doc に
/// 経緯がある）。ここへデリゲートメソッドを足すときも同じ理由で completion-handler 版を選ぶ。
@MainActor
final class WebKitSurfaceEventBridge: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private weak var navigation: (any SurfaceNavigationObserver)?
    private weak var bridge: (any SurfaceBridgeMessageObserver)?

    init(
        navigation: any SurfaceNavigationObserver,
        bridge: any SurfaceBridgeMessageObserver
    ) {
        self.navigation = navigation
        self.bridge = bridge
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        RenderDiagnostics.log("surface \(RenderDiagnostics.id(webView)): didFinish")
        navigation?.surfaceDidFinishLoad()
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error
    ) {
        RenderDiagnostics.log("surface \(RenderDiagnostics.id(webView)): didFailProvisional (\(error))")
        navigation?.surfaceDidFailLoad()
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        RenderDiagnostics.log("surface \(RenderDiagnostics.id(webView)): didFail (\(error))")
        navigation?.surfaceDidFailLoad()
    }

    /// WebContent プロセスが落ちたとき。**ナビゲーションのコールバックは 1 つも来ない**
    /// ——didFinish も didFail も発火しないため、この経路を握っていないと準備完了が
    /// 永久に来ない(TASK-607 の調査で、これが「60 秒待っても ready にならない」を
    /// 作りうる分岐だと分かった)。いまは記録だけで、扱いは切り分けの結果を見て決める。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        RenderDiagnostics.log("surface \(RenderDiagnostics.id(webView)): webContentProcessDidTerminate")
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let navigation else {
            RenderDiagnostics.log("surface: decidePolicy を cancel (観測者が解放済み)")
            decisionHandler(.cancel)
            return
        }
        let kind: SurfaceNavigationRequest.Kind = switch navigationAction.navigationType {
        case .linkActivated: .linkActivated
        case .other: .programmatic
        // フォーム送信・戻る/進む・リロード。まとめて「通さない側」へ写す。
        // ここを .programmatic へ寄せると、それらが黙って通るようになる。
        default: .otherInteraction
        }
        let request = SurfaceNavigationRequest(
            kind: kind,
            url: navigationAction.request.url,
            modifiers: navigationAction.modifierFlags
        )
        switch navigation.surfaceShouldNavigate(request) {
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        bridge?.surfaceDidReceiveBridgeMessage(name: message.name, body: message.body)
    }
}
