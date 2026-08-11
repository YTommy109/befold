@testable import befold
import Foundation
import Testing

/// 一覧の引き当て述語(TASK-442.2 で SidebarNavigator から移設)を検証する。
@Suite
@MainActor
struct FileListModelLookupTests {
    private let directory = URL(fileURLWithPath: "/tmp/befold-list-lookup")

    private func makeModel(entries: [FileListEntry]) -> FileListModel {
        let model = FileListModel(currentDirectory: directory, entries: [], selection: nil)
        model.setEntries(entries, for: directory)
        return model
    }

    @Test("フォルダーの正規化キーが一致する行の URL を返す")
    func findsFolderByPathKey() {
        let folder = directory.appendingPathComponent("sub")
        let model = makeModel(entries: [FileListEntry(url: folder, kind: .folder)])

        #expect(model.folderEntryURL(forKey: folder.normalizedPathKey) == folder)
    }

    @Test("同じキーの行がファイルならフォルダーとしては引き当てない")
    func ignoresNonFolderEntry() {
        let file = directory.appendingPathComponent("note.md")
        let model = makeModel(entries: [FileListEntry(url: file, kind: .file)])

        #expect(model.folderEntryURL(forKey: file.normalizedPathKey) == nil)
        #expect(model.folderEntryURL(forKey: "/nowhere") == nil)
    }

    @Test("一覧にある行は一覧側の URL を返す")
    func returnsEntryURLWhenPresent() {
        let file = directory.appendingPathComponent("note.md")
        let model = makeModel(entries: [FileListEntry(url: file, kind: .file)])

        #expect(model.matchingEntryURL(for: file) == file)
    }

    @Test("一覧に無ければ渡した URL をそのまま返す")
    func returnsGivenURLWhenAbsent() {
        let model = makeModel(entries: [])
        let missing = directory.appendingPathComponent("missing.md")

        #expect(model.matchingEntryURL(for: missing) == missing)
    }
}
