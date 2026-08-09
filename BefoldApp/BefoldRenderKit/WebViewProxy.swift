import WebKit

/// SwiftUI 内部で生成される WKWebView を AppKit 側（ViewerWindowController の
/// メニューアクション）へ橋渡しするための弱参照ホルダー。
/// ズーム・印刷などレスポンダチェーン経由のアクションから WebView を操作するのに使う。
@MainActor
public final class WebViewProxy {
    public weak var webView: WKWebView?
    /// HTML ファイルが loadFileURL で直接ロードされているか（viewer.html の JS ズームが使えないモード）。
    public var isDirectHTMLMode = false
    /// SwiftUI 内部で生成される ViewerRenderer を AppKit 側へ橋渡しする弱参照。
    /// WebView そのものではなく描画状態(描画済みミラー)への操作(rename の追随など)に使う。
    /// renderer が proxy を強参照するため、逆向きは weak で輪を閉じない。
    public weak var renderer: ViewerRenderer?

    public init() {}
}
