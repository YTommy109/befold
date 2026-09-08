import Foundation
import WebKit

/// `RenderSurface` の WKWebView 実装。
///
/// **描画面に対する WKWebView 固有の操作はここへ閉じる。** 上の層
/// （`ViewerScriptDispatcher` / `PageZoomProjector` / `DirectHTMLModeController` 等）は
/// `RenderSurface` しか知らず、WebKit の型に触らない。
///
/// WKWebView 参照を包むだけで、自前の状態は持たない。参照型にしてあるのは
/// `zoom` / `isContentJavaScriptEnabled` が `any RenderSurface` 越しに代入される
/// ため（値型だとコピーへの代入になり、optional chain 越しでは代入自体が書けない）。
/// 生成は `ViewerRenderer.webView` の setter 1 箇所だけで、そこが唯一の状態
/// （`surface`）を更新する。
public final class WebKitRenderSurface: RenderSurface {
    public let webView: WKWebView

    public init(_ webView: WKWebView) {
        self.webView = webView
    }

    public func evaluateScript(_ script: String, completion: ((Error?) -> Void)?) {
        guard let completion else {
            // completionHandler を省略すると async のオーバーロードが選ばれる文脈が
            // あるため、nil を明示して同期版へ固定する。
            webView.evaluateJavaScript(script, completionHandler: nil)
            return
        }
        webView.evaluateJavaScript(script) { _, error in completion(error) }
    }

    public func callScript(_ script: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(script, in: nil, contentWorld: .page)
    }

    public func loadLocalFile(_ url: URL, allowingReadAccessTo directory: URL) {
        webView.loadFileURL(url, allowingReadAccessTo: directory)
    }

    public func loadHTML(_ data: Data, mimeType: String, encoding: String, baseURL: URL) {
        webView.load(data, mimeType: mimeType, characterEncodingName: encoding, baseURL: baseURL)
    }

    public var zoom: Double {
        get { webView.pageZoom }
        set { webView.pageZoom = newValue }
    }

    public var currentURL: URL? {
        webView.url
    }

    public var isContentJavaScriptEnabled: Bool {
        get { webView.configuration.defaultWebpagePreferences.allowsContentJavaScript }
        set { webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = newValue }
    }

    public func setDocumentOwnsCanvas(_ documentOwns: Bool) {
        // drawsBackground は公開 API に無く KVC で触るしかない。呼び出し側へ
        // 漏らさないよう、この型の内側に閉じてある。
        //
        // **極性は反転しない。** `drawsBackground == true` が「WebKit が地を塗る」
        // = 文書が canvas を所有する、で意味が一致する（既定は透過の false）。
        // 反転させると直接 HTML モードの明暗が逆になる
        // （`ViewerCanvasOwnershipTests` が実測のピクセル値を根拠に固定している）。
        webView.setValue(documentOwns, forKey: "drawsBackground")
    }
}
