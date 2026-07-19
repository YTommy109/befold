import AppKit
import BefoldKit
import BefoldRenderKit
import WebKit

/// ViewerWindowController のメニュー/ツールバーから届く WebView 操作コマンド
/// (ズーム・印刷・検索・スクロール位置保存)の実処理を担う。
/// webViewProxy 越しの `guard let webView` + `evaluateJavaScript` の反復を
/// evaluate ヘルパーへ畳み、ウィンドウコントローラ本体を GUI 結線に専念させる。
@MainActor
final class WebViewCommandController {
    private let webViewProxy: WebViewProxy
    private let perFileState: PerFileStateStore
    /// 現在表示中ファイルの URL。rename/switch で書き換わるため値を捕捉せず都度取得する。
    private let currentURL: () -> URL

    init(
        webViewProxy: WebViewProxy,
        perFileState: PerFileStateStore,
        currentURL: @escaping () -> URL
    ) {
        self.webViewProxy = webViewProxy
        self.perFileState = perFileState
        self.currentURL = currentURL
    }

    /// find/findNext/findPrevious の有効判定に使う。HTML 直接ロード中は viewer.html の
    /// JS が存在しないため検索系メニューを無効化する。
    var isDirectHTMLMode: Bool {
        webViewProxy.isDirectHTMLMode
    }

    /// webView が生存していれば script を評価する。生存前・破棄後は無視する。
    private func evaluate(_ script: String) {
        guard let webView = webViewProxy.webView else { return }
        webView.evaluateJavaScript(script)
    }

    // MARK: - Zoom

    /// 現在のファイルの保存倍率を WebView に適用する。
    /// 初期ロード時の倍率注入(ViewerBridge.applyZoomScript)と同じ経路で反映させる。
    func applyStoredZoom() {
        evaluate(ViewerBridge.applyZoomScript(perFileState.zoom.zoom(for: currentURL())))
    }

    /// 直接 HTML モードでは pageZoom を transform で変換して保存し、
    /// それ以外は viewer.js のズーム実装(script)へ委譲する。
    private func performZoom(directHTML transform: (Double) -> Double, script: String) {
        guard let webView = webViewProxy.webView else { return }
        if webViewProxy.isDirectHTMLMode {
            let newZoom = transform(webView.pageZoom)
            webView.pageZoom = newZoom
            perFileState.zoom.setZoom(newZoom, for: currentURL())
        } else {
            webView.evaluateJavaScript(script)
        }
    }

    func zoomIn() {
        performZoom(
            directHTML: { min(ZoomStore.maxZoom, $0 + ZoomStore.zoomStep) },
            script: ViewerBridge.zoomInScript
        )
    }

    func zoomOut() {
        performZoom(
            directHTML: { max(ZoomStore.minZoom, $0 - ZoomStore.zoomStep) },
            script: ViewerBridge.zoomOutScript
        )
    }

    func resetZoom() {
        performZoom(
            directHTML: { _ in ZoomStore.defaultZoom },
            script: ViewerBridge.zoomResetScript
        )
    }

    // MARK: - Print

    /// WebView の描画内容を指定ウィンドウ上のシートとして印刷する。
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

    // MARK: - Find

    func openFind() {
        runFindScript(ViewerBridge.openFindScript)
    }

    func findNext() {
        runFindScript(ViewerBridge.findNextScript)
    }

    func findPrevious() {
        runFindScript(ViewerBridge.findPrevScript)
    }

    /// find/findNext/findPrevious 共通のガードと JS 実行。
    /// HTML ファイルの直接ロード表示中は viewer.html の JS が存在しないためスキップする。
    private func runFindScript(_ script: String) {
        guard !webViewProxy.isDirectHTMLMode else { return }
        evaluate(script)
    }

    // MARK: - Scroll position

    /// WebView に現在のスクロール位置を問い合わせ、指定した URL・モードのキーへ保存する。
    /// ファイル/モード切替の直前に、切替後の現在 URL / モードに依存せず退場側の位置を
    /// 確定させるために使う。
    func saveCurrentScrollPosition(for url: URL, mode: ViewerBridge.ViewMode) {
        guard let webView = webViewProxy.webView else { return }
        webView.evaluateJavaScript(ViewerBridge.currentScrollPositionScript) { [perFileState] result, _ in
            guard let position = (result as? NSNumber)?.doubleValue else { return }
            perFileState.scrollPosition.setScrollPosition(position, for: url, mode: mode)
        }
    }
}
