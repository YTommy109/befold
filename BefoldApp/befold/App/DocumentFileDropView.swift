import AppKit
import BefoldKit

/// 描画面の上でファイルドロップだけを受ける。通常のマウス入力は下のビューへ通す。
/// WebKit・PDFKit・空タブで同じ入口を共有し、描画エンジンに文書を開く責務を持たせない。
final class DocumentFileDropView: NSView {
    private let onDrop: ([URL]) -> Void

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    /// コンテンツを取り付けた後に一度だけ呼ぶ。ビューの寿命はウィンドウの内容と一致する。
    static func install(on window: NSWindow) {
        guard let content = window.contentViewController else { return }
        // NSSplitView の直下へ足すと、ドロップ面が第三の分割ペインになる。
        // 元のコントローラを子として保持し、レイアウト管理の外側へ重ねる。
        window.contentViewController = nil
        let container = NSViewController()
        container.view = NSView(frame: content.view.frame)
        container.addChild(content)
        content.view.frame = container.view.bounds
        content.view.autoresizingMask = [.width, .height]
        container.view.addSubview(content.view)
        let overlay = DocumentFileDropView { [weak window] urls in
            guard let window else { return }
            AppDelegate.shared?.openFilesInTabs(urls, relativeTo: window)
        }
        overlay.frame = container.view.bounds
        overlay.autoresizingMask = [.width, .height]
        container.view.addSubview(overlay, positioned: .above, relativeTo: nil)
        window.contentViewController = container
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        files(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        acceptDrop(from: sender.draggingPasteboard)
    }

    /// 対応ファイルを一度のバッチとして渡す。呼び出し側が順序を保ってタブへ開く。
    func acceptDrop(from pasteboard: NSPasteboard) -> Bool {
        let urls = files(from: pasteboard)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    private func files(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL] ?? []
        return Self.supportedFiles(in: urls)
    }

    /// drag の高頻度経路では I/O を行わない。ディレクトリの最終判定はオープン時に行う。
    nonisolated static func supportedFiles(in urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL && !$0.hasDirectoryPath && FileType.isSupported($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
