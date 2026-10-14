import AppKit
@testable import befold
import SwiftUI
import Testing

/// ウィンドウがキーに戻ったとき、自前列挙の一覧が取り直される(TASK-706 / TASK-707)。
/// 実物の FolderListingView を窓に載せ、裏の NSTableView の行数で観測する。
@MainActor
struct FolderListingKeyReturnRefreshTests {
    private func tableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews {
            if let found = tableView(in: sub) { return found }
        }
        return nil
    }

    private func spin(until condition: () -> Bool) async {
        for _ in 0 ..< 100 where !condition() {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("キー復帰で、外部で追加されたファイルが一覧に現れる")
    func keyReturnRelists() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyReturn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a".utf8).write(to: dir.appendingPathComponent("a.md"))

        let filter = FileListModel(currentDirectory: dir, entries: [], selection: nil).listFilter
        let view = FolderListingView(
            directory: dir, sortOrder: .foldersFirst, showHiddenFiles: false, filter: filter,
            onSelectFile: { _ in }, onNavigateToFolder: { _ in }
        )
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()

        await spin { (tableView(in: host)?.numberOfRows ?? 0) == 1 }
        #expect(tableView(in: host)?.numberOfRows == 1)

        try Data("b".utf8).write(to: dir.appendingPathComponent("b.md"))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        await spin { (tableView(in: host)?.numberOfRows ?? 0) == 2 }
        #expect(tableView(in: host)?.numberOfRows == 2)
    }
}
