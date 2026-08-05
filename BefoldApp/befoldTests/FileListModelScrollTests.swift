import AppKit
@testable import befold
import Foundation
import Testing

/// 選択を動かしても一覧がスクロールせず、選択行が可視領域の外に出たまま見えなくなる
/// 問題の回帰テスト(#414)。矢印キーは FileListView 側で `.handled` にしているため
/// NSTableView 自身の自動スクロールは走らず、選択の書き込み点から明示的に要求する。
@Suite
@MainActor
struct FileListModelScrollTests {
    /// scrollRowToVisible の要求行を記録するスパイ。スクロールビューに入っていない
    /// NSTableView は実際の可視領域が動かないため、遷移結果ではなく
    /// 「どの行を可視にするよう要求したか」を検証する。
    private final class SpyTableView: NSTableView {
        private(set) var scrolledRows: [Int] = []
        override func scrollRowToVisible(_ row: Int) {
            scrolledRows.append(row)
        }
    }

    private let directory = URL(fileURLWithPath: "/tmp/FileListModelScrollTests")

    private func makeEntries(_ count: Int) -> [FileListEntry] {
        (0 ..< count).map {
            FileListEntry(url: directory.appendingPathComponent("file\($0).mmd"), kind: .file)
        }
    }

    private func makeModel(entries: [FileListEntry]) -> (FileListModel, SpyTableView) {
        let model = FileListModel(currentDirectory: directory, entries: entries, selection: nil)
        let tableView = SpyTableView()
        model.sidebarTableView = tableView
        return (model, tableView)
    }

    /// スクロール要求は NSTableView が新しい行を反映したあとになるよう次のランループへ
    /// 遅らせてある。先に積まれたその要求が走り終わってから検証するために 1 回譲る。
    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test("選択を動かすと、その行を可視にするようスクロールを要求する")
    func movingSelectionScrollsRowIntoView() async {
        let entries = makeEntries(100)
        let (model, tableView) = makeModel(entries: entries)

        model.selection = entries[80].id
        await drainMainQueue()

        #expect(tableView.scrolledRows == [80])
    }

    /// フォルダー再訪時の選択復元は、選択を書いたあとに一覧が届く。書いた瞬間の
    /// 一覧で行番号を引くと見つからず、スクロールが空振りする。
    @Test("一覧が届く前に選択を書いても、届いた一覧での行番号でスクロールを要求する")
    func selectionWrittenBeforeEntriesArriveScrollsToRowInNewList() async {
        let (model, tableView) = makeModel(entries: [])
        let entries = makeEntries(100)

        model.selection = entries[42].id
        model.setEntries(entries, for: directory)
        await drainMainQueue()

        #expect(tableView.scrolledRows == [42])
    }

    @Test("選択を消したときはスクロールを要求しない")
    func clearingSelectionDoesNotScroll() async {
        let entries = makeEntries(10)
        let (model, tableView) = makeModel(entries: entries)

        model.selection = nil
        await drainMainQueue()

        #expect(tableView.scrolledRows.isEmpty)
    }
}
