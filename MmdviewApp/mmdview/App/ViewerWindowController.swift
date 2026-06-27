import AppKit
import SwiftUI

final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    let store: ViewerStore
    var onClose: (() -> Void)?

    init(fileURL: URL) {
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
        window.setFrameAutosaveName("Viewer-\(safeName)")
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let contentView = ViewerContentView(store: store)
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        store.openFile(fileURL)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func windowWillClose(_ notification: Notification) {
        store.close()
        onClose?()
    }
}
