import BefoldKit
@testable import BefoldRenderKit
import WebKit

/// JS → Swift の postMessage 経路を検証するテストで共有するスタブ群。
/// ViewerRendererMessageHandlingTests と ViewerRendererResolveReferencesTests の双方から使う。
enum ViewerRendererMessageStubs {
    /// WKScriptMessage は公開イニシャライザを持たないため、name/body を差し替えた
    /// サブクラスでハンドラへ任意のメッセージを注入する。
    final class ScriptMessage: WKScriptMessage {
        private let stubName: String
        private let stubBody: Any

        init(name: String, body: Any) {
            stubName = name
            stubBody = body
            super.init()
        }

        override var name: String {
            stubName
        }

        override var body: Any {
            stubBody
        }
    }

    /// 評価された JS を検証するため、evaluateJavaScript をフックして
    /// 渡されたスクリプト文字列を順に記録する WKWebView サブクラス。
    @MainActor
    final class WebView: WKWebView {
        /// 評価されたスクリプトを順に記録する(応答順の検証に使う)。
        var evaluatedScripts: [String] = []
        var lastEvaluatedScript: String? {
            evaluatedScripts.last
        }

        override func evaluateJavaScript(
            _ javaScriptString: String,
            completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil
        ) {
            evaluatedScripts.append(javaScriptString)
        }
    }

    /// 各通知をクロージャへ横流しするスタブ delegate。
    /// ViewerRenderer.delegate は weak なので、テスト側でこのインスタンスを
    /// ローカル変数に保持し続けること(即座に解放されると通知が届かない)。
    @MainActor
    final class Delegate: ViewerRendererDelegate {
        var onZoomChanged: ((Double, URL?) -> Void)?
        var onOpenReference: ((String, OpenDisposition) -> Void)?
        var onResolveReferences: (([String]) async -> [String: String])?
        var onLoadMoreLines: (() async -> LoadMoreLinesResult?)?
        var onContextMenu: ((String) -> Void)?

        func renderer(_: ViewerRenderer, didChangeZoom zoom: Double, for url: URL?) {
            onZoomChanged?(zoom, url)
        }

        func renderer(_: ViewerRenderer, didActivateReference href: String, disposition: OpenDisposition) {
            onOpenReference?(href, disposition)
        }

        func renderer(_: ViewerRenderer, resolveReferences paths: [String]) async -> [String: String] {
            await onResolveReferences?(paths) ?? [:]
        }

        func rendererDidRequestMoreLines(_: ViewerRenderer) async -> LoadMoreLinesResult? {
            await onLoadMoreLines?() ?? nil
        }

        func renderer(_: ViewerRenderer, didRequestContextMenuFor href: String) {
            onContextMenu?(href)
        }
    }

    @MainActor
    static func dispatch(_ renderer: ViewerRenderer, name: String, body: Any) {
        renderer.messageRouter.userContentController(
            WKUserContentController(),
            didReceive: ScriptMessage(name: name, body: body)
        )
    }
}
