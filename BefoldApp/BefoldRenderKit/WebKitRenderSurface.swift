import BefoldKit
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
/// この型を作るのは `make(for:…)` と、テストが面を差し替える場合の直接生成だけ。
/// レンダラ側の状態（`ViewerRenderer.surface`）を更新するのは `ViewerRenderer.adopt`
/// で、`make(for:…)` がその中から呼ぶ。
public final class WebKitRenderSurface: RenderSurface {
    public let webView: WKWebView

    public init(_ webView: WKWebView) {
        self.webView = webView
    }

    /// 描画面を構成して返す。**構成済みの面を得る唯一の入口。**
    ///
    /// `WKWebView` そのものを組み立てるのは `ViewerWebViewFactory`（configuration・
    /// user script の注入・postMessage ハンドラの登録）で、生成をそこ 1 箇所に限る規約は
    /// `.swiftlint.yml` の `webview_creation_outside_webkit_layer` が守っている。
    /// この 2 つは別のことを言っている——**組み立ての置き場が factory、呼び出し側から
    /// 見た入口がここ**。factory をこの型へ物理的に畳まないのは、責務が 4 つある
    /// 330 行の型になり、型を小さく保つ方針と逆になるため。
    ///
    /// 生成した面には viewer.html まで読み込ませて返す（呼び出し側が読み込みを
    /// 忘れた面を配れないようにするため）。
    static func make(
        options: ViewerWebViewFactory.Options,
        eventHandler: WebKitSurfaceEventBridge
    ) -> WebKitRenderSurface {
        let webView = ViewerWebViewFactory.makeWebView(
            options: options, messageHandler: eventHandler
        )
        webView.navigationDelegate = eventHandler
        let surface = WebKitRenderSurface(webView)
        ViewerWebViewFactory.loadViewerHTML(into: surface)
        return surface
    }

    /// レンダラと結びついた描画面を構成して返す。**構成経路はこれ 1 本。**
    ///
    /// 実体の NSView を要るホスト（`NSViewRepresentable` の `makeNSView`、QuickLook の
    /// プレビュー）が使う。戻り値が具体型なので降格が要らず、失敗しうる経路が無い
    /// （TASK-599 以前はアプリ側で `as?` に失敗したら `preconditionFailure` していた）。
    ///
    /// この入口を `ViewerRenderer` ではなくこちらへ置くことで、`ViewerRenderer` は
    /// WKWebView を知らないままでいられる。
    @MainActor
    public static func make(
        for renderer: ViewerRenderer,
        initialZoom: Double,
        findOptionsPreference: FindOptionsPreference?,
        codeFontFamily: String? = nil,
        codeFontSizePoints: Double? = nil,
        csvGrouping: Bool = true,
        csvNegativeStyle: CsvNegativeStyle = .plain,
        headingJumpLevels: HeadingJumpLevels = .default
    ) -> WebKitRenderSurface {
        let surface = make(
            options: renderer.surfaceOptions(
                initialZoom: initialZoom, findOptionsPreference: findOptionsPreference,
                codeFontFamily: codeFontFamily, codeFontSizePoints: codeFontSizePoints,
                csvGrouping: csvGrouping, csvNegativeStyle: csvNegativeStyle,
                headingJumpLevels: headingJumpLevels
            ),
            eventHandler: renderer.surfaceEventBridge
        )
        renderer.adopt(
            surface, initialZoom: initialZoom, findOptionsPreference: findOptionsPreference
        )
        return surface
    }

    public func applyRemoteLoadPolicy(then completion: @escaping () -> Void) {
        RemoteLoadBlocker.apply(to: webView, then: completion)
    }

    public func removeMessageHandlers(named names: [String]) {
        for name in names {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
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
