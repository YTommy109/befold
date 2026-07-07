@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct NavigationHistoryTests {
    private let dir = URL(fileURLWithPath: "/files")
    private func entry(_ name: String) -> HistoryEntry {
        HistoryEntry(directory: dir, file: dir.appendingPathComponent(name))
    }

    @Test("push で履歴が積まれ現在地が末尾になる")
    func pushAppendsAndAdvances() {
        let history = NavigationHistory()
        #expect(history.canGoBack == false)

        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))

        #expect(history.entries.count == 2)
        #expect(history.currentIndex == 1)
        #expect(history.canGoBack == true)
        #expect(history.canGoForward == false)
    }

    @Test("同一スナップショットの連続 push は無視される")
    func duplicatePushIsIgnored() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("a.mmd"))

        #expect(history.entries.count == 1)
        #expect(history.currentIndex == 0)
    }

    @Test("move(by:) で戻り currentIndex とエントリが変わる")
    func moveBackReturnsEntry() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))

        let moved = history.move(by: -1)

        #expect(moved == entry("a.mmd"))
        #expect(history.currentIndex == 0)
        #expect(history.canGoForward == true)
    }

    @Test("範囲外の move は nil を返し現在地を変えない")
    func moveOutOfBoundsReturnsNil() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))

        #expect(history.move(by: -1) == nil)
        #expect(history.currentIndex == 0)
        #expect(history.move(by: 5) == nil)
        #expect(history.currentIndex == 0)
    }

    @Test("戻った後の新規 push で進む履歴が破棄される")
    func pushTruncatesForwardHistory() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))
        history.push(entry("c.mmd"))
        _ = history.move(by: -2) // -> a

        history.push(entry("d.mmd"))

        #expect(history.entries.map(\.file?.lastPathComponent) == ["a.mmd", "d.mmd"])
        #expect(history.currentIndex == 1)
        #expect(history.canGoForward == false)
    }

    @Test("backEntries は新しい順、forwardEntries は近い順")
    func backAndForwardEntriesOrdering() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))
        history.push(entry("c.mmd"))
        _ = history.move(by: -1) // 現在 b（a<-b->c）

        #expect(history.backEntries().map(\.file?.lastPathComponent) == ["a.mmd"])
        #expect(history.forwardEntries().map(\.file?.lastPathComponent) == ["c.mmd"])
    }

    @Test("renameOccurred で履歴内の該当ファイルが差し替わる")
    func renameRemapsMatchingEntries() {
        let history = NavigationHistory()
        history.push(entry("old.mmd"))
        history.push(entry("b.mmd"))
        let new = dir.appendingPathComponent("new.mmd")

        history.renameOccurred(from: dir.appendingPathComponent("old.mmd"), to: new)

        #expect(history.entries[0].file?.lastPathComponent == "new.mmd")
        #expect(history.entries[1].file?.lastPathComponent == "b.mmd")
    }

    @Test("renameOccurred で別ディレクトリへ移動するとディレクトリも差し替わる")
    func renameRemapsDirectoryOnCrossDirectoryMove() {
        let history = NavigationHistory()
        let oldDir = URL(fileURLWithPath: "/old")
        let newDir = URL(fileURLWithPath: "/new")
        let oldFile = oldDir.appendingPathComponent("a.mmd")
        let newFile = newDir.appendingPathComponent("a.mmd")
        history.push(HistoryEntry(directory: oldDir, file: oldFile))
        history.push(HistoryEntry(directory: oldDir, file: oldDir.appendingPathComponent("b.mmd")))

        history.renameOccurred(from: oldFile, to: newFile)

        #expect(history.entries[0].directory.path == "/new")
        #expect(history.entries[0].file?.lastPathComponent == "a.mmd")
        #expect(history.entries[1].directory.path == "/old")
        #expect(history.entries[1].file?.lastPathComponent == "b.mmd")
    }
}
