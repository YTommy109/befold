import AppKit
import SwiftUI
import WebKit

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    private let store: ViewerStore
    private let webViewProxy = WebViewProxy()
    private(set) var fileURL: URL
    /// ウィンドウが閉じられたときに呼ばれるコールバック。AppDelegate がウィンドウ管理辞書から除去するために使用する。
    var onClose: (() -> Void)?

    // MARK: - Initialization

    init(fileURL: URL, zoomStore: ZoomStore) {
        self.fileURL = fileURL
        store = ViewerStore()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 400, height: 300)
        window.title = fileURL.lastPathComponent
        // タイトルバーにプロキシアイコンを表示し、Cmd+クリックのパス表示・
        // タイトルバーからのドラッグを有効にする
        window.representedURL = fileURL
        window.tabbingIdentifier = "ViewerWindow"
        window.collectionBehavior.insert(.fullScreenPrimary)
        let safeName = fileURL.path.replacingOccurrences(of: "/", with: "_")
        let autosaveName = "Viewer-\(safeName)"
        // 保存済みフレームがあれば復元し、なければ後段で中央配置する
        let hasSavedFrame = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let contentView = ViewerContentView(
            store: store,
            initialZoom: zoomStore.zoom(for: fileURL),
            onZoomChanged: { zoom in zoomStore.setZoom(zoom, for: fileURL) },
            webViewProxy: webViewProxy
        )
        window.contentView = NSHostingView(rootView: contentView)
        if !hasSavedFrame {
            window.center()
        }

        store.openFile(fileURL)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - Menu Actions

    /// View > Zoom In。WebView 内の JS ズーム実装を呼び出す。
    @objc func zoomIn(_ sender: Any?) {
        webViewProxy.webView?.evaluateJavaScript("_mmdZoomIn()")
    }

    /// View > Zoom Out。
    @objc func zoomOut(_ sender: Any?) {
        webViewProxy.webView?.evaluateJavaScript("_mmdZoomOut()")
    }

    /// View > Actual Size。倍率を 100% に戻す。
    @objc func resetZoom(_ sender: Any?) {
        webViewProxy.webView?.evaluateJavaScript("_mmdZoomReset()")
    }

    /// File > Print…。WebView の描画内容を印刷する。
    @objc func printDocument(_ sender: Any?) {
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

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        store.close()
        onClose?()
    }
}
