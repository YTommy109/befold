@testable import befold
import Foundation
import Testing

/// スライド窓の前後移動が使う「隣のファイル行」の解決(TASK-593.3)。
///
/// `FileListSnapshot` を直接組む純粋テスト。フォルダー行を飛ばすこと・端で止まること・
/// 絞り込みが反映されることを、ウィンドウを作らずに測る。
@MainActor
struct FileListSnapshotFileNeighbourTests {
    private let directory = URL(fileURLWithPath: "/tmp/FileListSnapshotFileNeighbourTests")

    private func entry(_ name: String, kind: FileListEntry.Kind = .file) -> FileListEntry {
        FileListEntry(url: directory.appendingPathComponent(name), kind: kind)
    }

    private func snapshot(_ entries: [FileListEntry]) -> FileListSnapshot {
        snapshot(entries, filter: FileListFilter())
    }

    private func snapshot(_ entries: [FileListEntry], filter: FileListFilter) -> FileListSnapshot {
        FileListSnapshot.make(entries: entries, in: directory, filter: filter)
    }

    @Test("次のファイルはフォルダー行を飛ばす")
    func nextFileSkipsFolders() {
        let first = entry("a.md")
        let folder = entry("sub", kind: .folder)
        let second = entry("b.md")

        let result = snapshot([first, folder, second]).nextFile(after: first.id)

        #expect(result?.url == second.url)
    }

    @Test("前のファイルもフォルダー行を飛ばす")
    func previousFileSkipsFolders() {
        let first = entry("a.md")
        let folder = entry("sub", kind: .folder)
        let second = entry("b.md")

        let result = snapshot([first, folder, second]).previousFile(before: second.id)

        #expect(result?.url == first.url)
    }

    @Test("フォルダー行が連続していても飛ばし切る")
    func nextFileSkipsConsecutiveFolders() {
        let first = entry("a.md")
        let folders = [entry("x", kind: .folder), entry("y", kind: .folder)]
        let last = entry("b.md")

        let result = snapshot([first] + folders + [last]).nextFile(after: first.id)

        #expect(result?.url == last.url)
    }

    @Test("最後のファイルで「次へ」は何も返さない（周回しない）")
    func nextFileStopsAtTheEnd() {
        let first = entry("a.md")
        let last = entry("b.md")

        #expect(snapshot([first, last]).nextFile(after: last.id) == nil)
    }

    @Test("最初のファイルで「前へ」は何も返さない（周回しない）")
    func previousFileStopsAtTheStart() {
        let first = entry("a.md")
        let last = entry("b.md")

        #expect(snapshot([first, last]).previousFile(before: first.id) == nil)
    }

    /// 末尾がフォルダー行のときも端として扱う（フォルダーを返して止まらない）。
    @Test("末尾がフォルダーなら「次へ」は何も返さない")
    func nextFileReturnsNilWhenOnlyFoldersRemain() {
        let file = entry("a.md")
        let folder = entry("sub", kind: .folder)

        #expect(snapshot([file, folder]).nextFile(after: file.id) == nil)
    }

    @Test("絞り込み中は絞り込み後の表示順で隣を決める")
    func neighboursFollowTheFilteredOrder() {
        let entries = [entry("alpha.md"), entry("beta.md"), entry("alps.md")]
        var filter = FileListFilter()
        filter.filterText = "al"

        let filtered = snapshot(entries, filter: filter)

        // beta.md は絞り込みで消えるので、alpha.md の次は alps.md になる。
        #expect(filtered.nextFile(after: entries[0].id)?.url == entries[2].url)
    }
}
