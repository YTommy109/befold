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

    @Test("SidebarTableFocuser.focus は tableView へフォーカスを要求する")
    func focusRequestsTableAsFirstResponder() {
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let tableView = NSTableView()
        window.contentView?.addSubview(tableView)
        let model = makeModel()
        model.tableFocuser.tableView = tableView

        model.tableFocuser.focus()

        #expect(window.requestedFirstResponder === tableView)
    }

    @Test("tableView が未解決でも落ちない")
    func focusWithoutTableIsNoOp() {
        let model = makeModel()

        model.tableFocuser.focus()

        #expect(model.tableFocuser.tableView == nil)
    }

    /// 畳んだ状態から初めてサイドバーを開く周期では、一覧の読み込みと List の初回
    /// レイアウトがフォーカス要求に間に合わず、`tableView`(行の背景から設定される)が
    /// まだ nil のことがある。要求を保持していないと、その回だけフォーカスが移らない
    /// (TASK-563 の実測: 復元起動の直後に ⌘S を押すと 3 回に 1 回再現した)。
    @Test("tableView が後から現れてもフォーカスを移す")
    func focusAppliesWhenTableArrivesLater() {
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let tableView = NSTableView()
        window.contentView?.addSubview(tableView)
        let model = makeModel()

        // 参照が現れる前に要求だけが来る順序。
        model.tableFocuser.focus()
        model.tableFocuser.tableView = tableView

        #expect(window.requestedFirstResponder === tableView)
    }

    /// 保持した要求は、サイドバーを畳んだ時点で捨てる。捨てないと、遅れて行が描かれた
    /// ときに「閉じたはずのサイドバー」がフォーカスを奪う(開始時の無効化)。
    @Test("畳んだ後に tableView が現れてもフォーカスを奪わない")
    func cancelledFocusDoesNotApplyLater() {
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let tableView = NSTableView()
        window.contentView?.addSubview(tableView)
        let model = makeModel()

        model.tableFocuser.focus()
        model.tableFocuser.cancelPendingFocus()
        model.tableFocuser.tableView = tableView

        #expect(window.requestedFirstResponder == nil)
    }
}
