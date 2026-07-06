import WebKit

/// SwiftUI 内部で生成される WKWebView を AppKit 側（ViewerWindowController の
/// メニューアクション）へ橋渡しするための弱参照ホルダー。
/// ズーム・印刷などレスポンダチェーン経由のアクションから WebView を操作するのに使う。
@MainActor
final class WebViewProxy {
    weak var webView: WKWebView?
}
