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

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        navigation?.surfaceDidFinishLoad()
    }

    func webView(
        _: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error
    ) {
        navigation?.surfaceDidFailLoad()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        navigation?.surfaceDidFailLoad()
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let navigation else {
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
