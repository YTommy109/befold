import AppKit
import SwiftUI
import WebKit

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    private let store: ViewerStore
    private let zoomStore: ZoomStore
    private let webViewProxy = WebViewProxy()
    private(set) var fileURL: URL
    /// ウィンドウが閉じられたときに呼ばれるコールバック。AppDelegate がウィンドウ管理辞書から除去するために使用する。
    var onClose: (() -> Void)?
    /// 開いているファイルが rename / move されたときに旧 URL・新 URL を通知するコールバック。
    /// AppDelegate がウィンドウ管理辞書のキー付け替えとセッション記録の更新に使用する。
    var onRename: ((_ old: URL, _ new: URL) -> Void)?

    // MARK: - Initialization

    init(fileURL: URL, zoomStore: ZoomStore) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
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
        let autosaveName = Self.autosaveName(for: fileURL)
        // 保存済みフレームがあれば復元し、なければ後段で中央配置する
        let hasSavedFrame = window.setFrameUsingName(autosaveName)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        // NSWindowController.init(window:) はウィンドウ側の frameAutosaveName を
        // コントローラの windowFrameAutosaveName（既定は空文字）で上書きするため、
        // autosave 名は super.init 後にコントローラ側プロパティへ設定する必要がある
        windowFrameAutosaveName = autosaveName
        window.delegate = self

        let contentView = ViewerContentView(
            store: store,
            initialZoom: zoomStore.zoom(for: fileURL),
            // 現在の fileURL は rename で書き換わるため、旧値を捕捉せず self 経由で参照する
            onZoomChanged: { [weak self] zoom in
                guard let self else { return }
                zoomStore.setZoom(zoom, for: self.fileURL)
            },
            webViewProxy: webViewProxy
        )
        window.contentView = NSHostingView(rootView: contentView)
        if !hasSavedFrame {
            window.center()
        }

        store.onFileRenamed = { [weak self] newURL in
            self?.handleRename(to: newURL)
        }
        store.openFile(fileURL)
    }

    /// フレーム autosave 名を URL から生成する。パス区切りをキーに使えない文字へ置換する。
    /// ZoomStore と同じ正規化パス（シンボリックリンク解決済み）を基準にし、
    /// 同一ファイルを指す別表記の URL を同じキーに集約する。
    private static func autosaveName(for url: URL) -> String {
        let safeName = url.normalizedPathKey.replacingOccurrences(of: "/", with: "_")
        return "Viewer-\(safeName)"
    }

    /// ファイルの rename / move をウィンドウに反映する。
    /// タイトル・representedURL・フレーム autosave 名・ズーム倍率キーを新パスへ移し、
    /// AppDelegate へ旧 URL・新 URL を通知する。
    private func handleRename(to newURL: URL) {
        let oldURL = fileURL
        guard newURL != oldURL else { return }
        fileURL = newURL

        if let window {
            window.title = newURL.lastPathComponent
            window.representedURL = newURL
            let oldAutosaveName = Self.autosaveName(for: oldURL)
            let newAutosaveName = Self.autosaveName(for: newURL)
            // 旧名のエントリを破棄してから、現在のフレームを新しい名前で保存し直す。
            // この順序なら旧新の正規化キーが一致する rename でも保存済みフレームが消えない。
            // autosave 名はコントローラ側プロパティ経由で変更しないと
            // windowFrameAutosaveName が旧名のままウィンドウ側と食い違う
            NSWindow.removeFrame(usingName: oldAutosaveName)
            window.saveFrame(usingName: newAutosaveName)
            windowFrameAutosaveName = newAutosaveName
        }

        zoomStore.migrateZoom(from: oldURL, to: newURL)
        onRename?(oldURL, newURL)
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
