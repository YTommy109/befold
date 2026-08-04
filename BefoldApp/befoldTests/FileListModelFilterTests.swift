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

    // MARK: - git 変更のみ表示(task-264)

    private func modifiedStatus() -> GitFileStatus {
        GitFileStatus(indexChange: nil, worktreeChange: .modified)
    }

    @Test("変更のみ表示 ON で、git 変更のあるファイルだけが残る")
    func changedFilesOnlyKeepsChangedFiles() {
        let changed = makeEntry("changed.md")
        let model = makeModel(entries: [changed, makeEntry("clean.md")])
        model.gitStatuses = [changed.pathKey: modifiedStatus()]
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])
    }

    @Test("変更のみ表示 ON でも、配下に変更を持つフォルダーと親移動行は残る")
    func changedFilesOnlyKeepsFoldersWithChangesAndParent() {
        let parent = makeEntry("..", kind: .parentNavigation)
        let folder = makeEntry("src", kind: .folder)
        let cleanFolder = makeEntry("docs", kind: .folder)
        let model = makeModel(entries: [parent, folder, cleanFolder])
        model.gitFolderStatuses = [folder.pathKey: GitFolderStatus(hasUnstaged: true)]
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["..", "src"])
    }

    @Test("変更のみ表示と filterText は AND で併用される")
    func changedFilesOnlyCombinesWithFilterText() {
        let changedMatching = makeEntry("README.md")
        let changedOther = makeEntry("notes.txt")
        let model = makeModel(entries: [changedMatching, changedOther, makeEntry("read-only.md")])
        model.gitStatuses = [
            changedMatching.pathKey: modifiedStatus(),
            changedOther.pathKey: modifiedStatus(),
        ]
        model.showChangedFilesOnly = true
        model.filterText = "read*"

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["README.md"])
    }

    @Test("git 状態が無い(非 git・取得失敗)ときはフィルター無効として全件を返す")
    func changedFilesOnlyDegradesWithoutGitStatuses() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: entries)
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }

    @Test("clean な状態しか無いときもフィルター無効として全件を返す")
    func changedFilesOnlyDegradesWhenAllStatusesAreClean() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: entries)
        model.gitStatuses = [entries[0].pathKey: GitFileStatus()]
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }

    @Test("変更のみ表示 OFF なら git 状態があっても絞り込まれない")
    func changedFilesOnlyOffKeepsAllEntries() {
        let entries = [makeEntry("changed.md"), makeEntry("clean.md")]
        let model = makeModel(entries: entries)
        model.gitStatuses = [entries[0].pathKey: modifiedStatus()]

        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }
}
