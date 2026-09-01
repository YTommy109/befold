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

    /// キーボードのフォーカスを**この面へ移す**。
    ///
    /// viewer.html 内のキー処理（`viewer-src/keyboard.ts` の document レベルの keydown）は、
    /// WKWebView が窓の first responder でなければ届かない。サイドバーが first responder を
    /// 握ったままだと、スペースや矢印が本文へ来ない。
    ///
    /// **1 周待つ。** SwiftUI が面を組み終える前に呼ぶと、その後の View の更新で
    /// first responder が外れる（PDF 面で実測した挙動と同じ / TASK-578.2）。
    ///
    /// **ユーザーが明示的に本文を選んだときだけ呼ぶこと。** 開いた瞬間に奪うと、
    /// サイドバーを矢印で流し読みしている最中にフォーカスを持って行かれる（TASK-581）。
    public func focusSurface() {
        let surface = webView
        DispatchQueue.main.async {
            guard let surface, let window = surface.window else { return }
            window.makeFirstResponder(surface)
        }
    }
}
