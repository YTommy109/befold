import AppKit
import BefoldKit
import BefoldRenderKit
import WebKit

/// `DocumentRendering` の WKWebView 実装(ADR 0002 段 4 の adapter)。
///
/// WebView の生存確認・ViewerBridge の JS 文字列・直接 HTML モードでの pageZoom 操作という
/// 「どう実現するか」をここに閉じる。呼び出し側は意図だけを伝える。
@MainActor
final class WebViewDocumentRenderer: DocumentRendering {
    private let webViewProxy: WebViewProxy
    /// 倍率の刻みと上下限。直接 HTML モードでは viewer.js を介さず自前で計算する。
    private let zoomStep: Double
    private let minZoom: Double
    private let maxZoom: Double
    private let defaultZoom: Double

    init(
        webViewProxy: WebViewProxy,
        zoomStep: Double = ZoomStore.zoomStep,
        minZoom: Double = ZoomStore.minZoom,
        maxZoom: Double = ZoomStore.maxZoom,
        defaultZoom: Double = ZoomStore.defaultZoom
    ) {
        self.webViewProxy = webViewProxy
        self.zoomStep = zoomStep
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.defaultZoom = defaultZoom
    }

    var isDirectHTMLMode: Bool {
        webViewProxy.isDirectHTMLMode
    }

    func applyZoom(_ zoom: Double) {
        evaluate(ViewerBridge.applyZoomScript(zoom))
    }

    func applyCodeFont(family: String?, points: Double?) {
        evaluate(ViewerBridge.applyCodeFontScript(family: family, points: points))
    }

    func changeZoom(_ change: ZoomChange) -> Double? {
        guard let webView = webViewProxy.webView else { return nil }
        guard isDirectHTMLMode else {
            webView.evaluateJavaScript(script(for: change))
            return nil
        }
        let newZoom = directHTMLZoom(for: change, current: webView.pageZoom)
        webView.pageZoom = newZoom
        return newZoom
    }

    func openFind() {
        evaluate(ViewerBridge.openFindScript)
    }

    func findNext() {
        evaluate(ViewerBridge.findNextScript)
    }

    func findPrevious() {
        evaluate(ViewerBridge.findPrevScript)
    }

    func openJump(kind: String) {
        evaluate(ViewerBridge.openJumpScript(kind: kind))
    }

    func closeJump() {
        evaluate(ViewerBridge.closeJumpScript)
    }

    func jumpNext() {
        evaluate(ViewerBridge.jumpNextScript)
    }

    func jumpPrevious() {
        evaluate(ViewerBridge.jumpPrevScript)
    }

    func printDocument(over window: NSWindow?) {
        guard let window, let webView = webViewProxy.webView else { return }
        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        let operation = webView.printOperation(with: printInfo)
        // WKWebView の printOperation はビューのフレームが zero のままだと
        // 白紙になるため、印刷対象の用紙サイズを明示する
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func currentScrollPosition(_ completion: @escaping (Double) -> Void) {
        guard let webView = webViewProxy.webView else { return }
        webView.evaluateJavaScript(ViewerBridge.currentScrollPositionScript) { result, _ in
            guard let position = (result as? NSNumber)?.doubleValue else { return }
            completion(position)
        }
    }

    func noteRename(from oldURL: URL, to newURL: URL) {
        // ミラーの差し替えと JS 側文書パスの差し替えを 1 つの同期区間で行うため、
        // JS 文字列をここで組まず ViewerRenderer に委ねる(片方だけ写すと、リネーム
        // 再描画の扱いと保存キーが食い違う)。WebView 生成前は renderer 未接続で no-op。
        webViewProxy.renderer?.handleRename(from: oldURL, to: newURL)
    }

    // MARK: - Private

    /// WebView が生存していれば script を評価する。生存前・破棄後は無視する。
    private func evaluate(_ script: String) {
        guard let webView = webViewProxy.webView else { return }
        webView.evaluateJavaScript(script)
    }

    private func script(for change: ZoomChange) -> String {
        switch change {
        case .zoomIn: ViewerBridge.zoomInScript
        case .zoomOut: ViewerBridge.zoomOutScript
        case .reset: ViewerBridge.zoomResetScript
        }
    }

    private func directHTMLZoom(for change: ZoomChange, current: Double) -> Double {
        switch change {
        case .zoomIn: min(maxZoom, current + zoomStep)
        case .zoomOut: max(minZoom, current - zoomStep)
        case .reset: defaultZoom
        }
    }
}
