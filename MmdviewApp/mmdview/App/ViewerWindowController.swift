import AppKit
import SwiftUI

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    private let store: ViewerStore
    /// ウィンドウが閉じられたときに呼ばれるコールバック。AppDelegate がウィンドウ管理辞書から除去するために使用する。
    var onClose: (() -> Void)?

    // MARK: - Initialization

    init(fileURL: URL, zoomStore: ZoomStore) {
        store = ViewerStore()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 400, height: 300)
        window.title = fileURL.lastPathComponent
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
            onZoomChanged: { zoom in zoomStore.setZoom(zoom, for: fileURL) }
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

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        store.close()
        onClose?()
    }
}
