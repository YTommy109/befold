import AppKit
@testable import befold
import Foundation
import Testing

/// サイドバーを開いた直後にアウトラインビュー(NSTableView)へフォーカスを移し、
/// フォルダー名をアクティブ(黒)表示にして矢印キー操作を可能にする挙動の回帰テスト(task-118)。
@Suite
@MainActor
struct FileListModelFocusTests {
    /// makeFirstResponder の要求先を記録するスパイ。空の NSTableView は
    /// 実描画前だと firstResponder を受理しないことがあるため、実際の遷移結果ではなく
    /// 「どのビューへフォーカスを要求したか」を検証する(ホストビューではなく table であることが本修正の要点)。
    private final class SpyWindow: NSWindow {
        private(set) var requestedFirstResponder: NSResponder?
        override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
            requestedFirstResponder = responder
            return super.makeFirstResponder(responder)
        }
    }

    private func makeModel() -> FileListModel {
        FileListModel(
            currentDirectory: URL(fileURLWithPath: "/tmp/FileListModelFocusTests"),
            entries: [],
            selection: nil
        )
    }

    @Test("focusSidebarTable は sidebarTableView へフォーカスを要求する")
    func focusRequestsTableAsFirstResponder() {
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let tableView = NSTableView()
        window.contentView?.addSubview(tableView)
        let model = makeModel()
        model.sidebarTableView = tableView

        model.focusSidebarTable()

        #expect(window.requestedFirstResponder === tableView)
    }

    @Test("sidebarTableView が未解決でリトライも尽きたときは何もしない(クラッシュしない)")
    func focusWithoutTableIsNoOp() {
        let model = makeModel()

        // 参照が無く再試行回数も 0 の場合、非同期のリトライをスケジュールせず即座に戻る。
        model.focusSidebarTable(retriesRemaining: 0)

        #expect(model.sidebarTableView == nil)
    }
}
