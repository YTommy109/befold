import BefoldKit
@testable import BefoldRenderKit
import Foundation

/// JS → Swift の postMessage 経路を検証するテストで共有するスタブ群。
/// ViewerRendererMessageHandlingTests と ViewerRendererResolveReferencesTests の双方から使う。
enum ViewerRendererMessageStubs {
    /// **WKWebView 実体を作らない描画面**（TASK-595.1）。
    ///
    /// `RenderSurface` は「この層が描画面へ送る操作」だけを持つので、記録する
    /// だけの実装で送出経路を丸ごと検証できる。WKWebView のサブクラス
    /// （下の `WebView`）と違い、WebKit のプロセスも viewer.html も要らない。
    @MainActor
    final class Surface: RenderSurface {
        /// 送られたスクリプトを順に記録する(順序の検証に使う)。
        var evaluatedScripts: [String] = []
        var lastEvaluatedScript: String? {
            evaluatedScripts.last
        }

        /// `loadLocalFile` / `loadHTML` の呼び出しを順に記録する。
        private(set) var loads: [URL] = []
        private(set) var documentOwnsCanvasHistory: [Bool] = []
        var zoom: Double = 1.0
        var currentURL: URL?
        var isContentJavaScriptEnabled = true
        /// `callScript` が返す値。既定は nil。
        var callScriptResult: Any?

        func evaluateScript(_ script: String, completion: ((Error?) -> Void)?) {
            evaluatedScripts.append(script)
            completion?(nil)
        }

        func callScript(_ script: String) async throws -> Any? {
            evaluatedScripts.append(script)
            return callScriptResult
        }

        func loadLocalFile(_ url: URL, allowingReadAccessTo _: URL) {
            loads.append(url)
            currentURL = url
        }

        func loadHTML(_: Data, mimeType _: String, encoding _: String, baseURL: URL) {
            loads.append(baseURL)
            currentURL = baseURL
        }

        func setDocumentOwnsCanvas(_ documentOwns: Bool) {
            documentOwnsCanvasHistory.append(documentOwns)
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
        renderer.messageRouter.surfaceDidReceiveBridgeMessage(name: name, body: body)
    }
}
