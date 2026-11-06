import AppKit
@testable import befold
import Testing

@Suite
@MainActor
struct DocumentFileDropTests {
    @Test("ドロップ面はサイドバーの分割ペインを増やさない")
    func overlayDoesNotBecomeASplitPane() {
        let split = NSSplitViewController()
        for _ in 0 ..< 2 {
            let pane = NSViewController()
            pane.view = NSView()
            split.addSplitViewItem(NSSplitViewItem(viewController: pane))
        }
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = split

        DocumentFileDropView.install(on: window)

        #expect(split.splitView.arrangedSubviews.count == 2)
        #expect(window.contentViewController?.children.contains(split) == true)
    }

    @Test("対応するローカルファイルだけを順序を保って受け取る")
    func filtersFilesWithoutChangingOrder() throws {
        let urls = try [
            URL(fileURLWithPath: "/mock/first.md"),
            URL(fileURLWithPath: "/mock/archive.zip"),
            #require(URL(string: "https://example.com/remote.md")),
            URL(fileURLWithPath: "/mock/folder.md", isDirectory: true),
            URL(fileURLWithPath: "/mock/second.CSV"),
            URL(fileURLWithPath: "/mock/third.pdf"),
        ]
        #expect(DocumentFileDropView.supportedFiles(in: urls) == [urls[0], urls[4], urls[5]])
    }

    @Test("複数のファイル URL を一度のバッチとして配信する")
    func acceptsOneOrderedBatch() {
        let files = ["a.md", "b.svg", "c.csv"].map { URL(fileURLWithPath: "/mock/\($0)") }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(files as [NSURL])
        var batches: [[URL]] = []
        let view = DocumentFileDropView { batches.append($0) }

        #expect(view.acceptDrop(from: pasteboard))
        #expect(batches == [files])
        #expect(view.hitTest(.zero) == nil)
    }

    @Test("対応ファイルが無ければドロップを拒否し、空タブを消費しない")
    func rejectsUnsupportedDrop() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([NSURL(fileURLWithPath: "/mock/unsupported.zip")])
        var delivered = false
        let view = DocumentFileDropView { _ in delivered = true }

        #expect(!view.acceptDrop(from: pasteboard))
        #expect(!delivered)
    }
}
