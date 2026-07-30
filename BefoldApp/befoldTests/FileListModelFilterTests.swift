@testable import befold
import Foundation
import Testing

/// ファイル名フィルター(task-185)の絞り込みロジックの回帰テスト。
@Suite
@MainActor
struct FileListModelFilterTests {
    private func makeEntry(_ name: String, kind: FileListEntry.Kind = .file) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListModelFilterTests/\(name)"), kind: kind)
    }

    private func makeModel(entries: [FileListEntry]) -> FileListModel {
        FileListModel(
            currentDirectory: URL(fileURLWithPath: "/tmp/FileListModelFilterTests"),
            entries: entries,
            selection: nil
        )
    }

    @Test("filterText が空なら entries と同じ一覧になる")
    func emptyFilterReturnsAllEntries() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: entries)

        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }

    @Test("filterText に一致するエントリだけが visibleEntries に残る")
    func filterNarrowsToMatchingEntries() {
        let entries = [makeEntry("README.md"), makeEntry("notes.txt")]
        let model = makeModel(entries: entries)
        model.filterText = "read"

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["README.md"])
    }

    @Test("親ディレクトリ(parentNavigation)はフィルター文字列に関わらず常に含まれる")
    func parentNavigationAlwaysVisible() {
        let entries = [makeEntry("..", kind: .parentNavigation), makeEntry("README.md")]
        let model = makeModel(entries: entries)
        model.filterText = "xyz"

        #expect(model.visibleEntries.map(\.kind) == [.parentNavigation])
    }
}
