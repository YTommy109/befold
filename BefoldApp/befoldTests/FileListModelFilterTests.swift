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

    /// FileListModel.applyGitStatus の sequence は「発行順」の連番であることが前提(ADR 0003)。
    /// テストは複数回の取得を模すため、呼ぶたびに新しい番号を払い出す。
    private final class GitStatusSequence {
        private var value = 0
        func next() -> Int {
            value += 1
            return value
        }
    }

    private let gitStatusSequence = GitStatusSequence()

    /// 本番と同じ経路で状態を組む。SidebarNavigator は必ず SidebarGitStatus を通して
    /// ファイル状態とフォルダー集約を同時に作るため、テストもそこを通す(TASK-290)。
    private func applyGitStatus(
        _ statuses: [String: GitFileStatus], to model: FileListModel, directory: URL? = nil
    ) {
        let target = directory ?? model.currentDirectory
        model.applyGitStatus(
            SidebarGitStatus(directoryKey: target.normalizedPathKey, statuses: statuses),
            for: target, sequence: gitStatusSequence.next()
        )
    }

    @Test("変更のみ表示 ON で、git 変更のあるファイルだけが残る")
    func changedFilesOnlyKeepsChangedFiles() {
        let changed = makeEntry("changed.md")
        let model = makeModel(entries: [changed, makeEntry("clean.md")])
        applyGitStatus([changed.pathKey: modifiedStatus()], to: model)
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])
    }

    @Test("変更のみ表示 ON でも、配下に変更を持つフォルダーと親移動行は残る")
    func changedFilesOnlyKeepsFoldersWithChangesAndParent() {
        let parent = makeEntry("..", kind: .parentNavigation)
        let folder = makeEntry("src", kind: .folder)
        let cleanFolder = makeEntry("docs", kind: .folder)
        let model = makeModel(entries: [parent, folder, cleanFolder])
        let nested = folder.url.appendingPathComponent("inner.md").normalizedPathKey
        applyGitStatus([nested: modifiedStatus()], to: model)
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["..", "src"])
    }

    @Test("変更のみ表示と filterText は AND で併用される")
    func changedFilesOnlyCombinesWithFilterText() {
        let changedMatching = makeEntry("README.md")
        let changedOther = makeEntry("notes.txt")
        let model = makeModel(entries: [changedMatching, changedOther, makeEntry("read-only.md")])
        applyGitStatus(
            [changedMatching.pathKey: modifiedStatus(), changedOther.pathKey: modifiedStatus()],
            to: model
        )
        model.showChangedFilesOnly = true
        model.filterText = "read*"

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["README.md"])
    }

    @Test("git 管理外(状態が未解決)ならフィルター無効として全件を返す")
    func changedFilesOnlyDegradesOutsideRepository() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: entries)
        model.showChangedFilesOnly = true

        #expect(model.gitStatus == nil)
        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }

    /// 変更ゼロのリポジトリは「空の状態」であって未解決ではない。ここを取り違えると
    /// トグルが黙って効かなくなる(TASK-285)。
    @Test("変更が 1 つも無いリポジトリでも絞り込みは効く(全件表示に戻らない)")
    func changedFilesOnlyAppliesInCleanRepository() {
        let parent = makeEntry("..", kind: .parentNavigation)
        let model = makeModel(entries: [parent, makeEntry("a.md"), makeEntry("b.md")])
        applyGitStatus([:], to: model)
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.kind) == [.parentNavigation])
    }

    /// 一覧と git 状態は別タスクで届く。別ディレクトリのものが残っている間は
    /// 絞り込まない(移動直後に一覧が消えるのを防ぐ)。
    @Test("状態が別ディレクトリのものなら絞り込まない")
    func changedFilesOnlyIgnoresStatusFromAnotherDirectory() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: entries)
        applyGitStatus([:], to: model, directory: URL(fileURLWithPath: "/tmp/OtherRepository"))
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }

    /// porcelain の既定は未追跡ディレクトリを `dir/` 1 レコードへ畳む。配下のファイルは
    /// 状態マップにキーを持たないが、未追跡であることに変わりはない(TASK-285)。
    @Test("未追跡ディレクトリ配下のファイルは、個別のキーが無くても残る")
    func changedFilesOnlyKeepsFilesUnderFoldedUntrackedDirectory() {
        let directory = URL(fileURLWithPath: "/tmp/FileListModelFilterTests/newdir")
        let inside = FileListEntry(url: directory.appendingPathComponent("b.md"), kind: .file)
        let model = FileListModel(currentDirectory: directory, entries: [inside], selection: nil)
        applyGitStatus([directory.normalizedPathKey: GitFileStatus(isUntracked: true)], to: model)
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["b.md"])
    }

    @Test("変更のみ表示 OFF なら git 状態があっても絞り込まれない")
    func changedFilesOnlyOffKeepsAllEntries() {
        let entries = [makeEntry("changed.md"), makeEntry("clean.md")]
        let model = makeModel(entries: entries)
        applyGitStatus([entries[0].pathKey: modifiedStatus()], to: model)

        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }

    // MARK: - 表示中の対象を残す(task-286)

    @Test("変更のみ表示 ON でも、選択中(表示中)の未変更ファイルは残る")
    func changedFilesOnlyKeepsPresentedEntry() {
        let changed = makeEntry("changed.md")
        let opened = makeEntry("README.md")
        let model = makeModel(entries: [changed, opened, makeEntry("other.md")])
        applyGitStatus([changed.pathKey: modifiedStatus()], to: model)
        model.selection = opened.id
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["changed.md", "README.md"])
    }

    @Test("選択が無ければ未変更ファイルは残らない")
    func changedFilesOnlyDropsUnchangedWithoutSelection() {
        let changed = makeEntry("changed.md")
        let model = makeModel(entries: [changed, makeEntry("README.md")])
        applyGitStatus([changed.pathKey: modifiedStatus()], to: model)
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])
    }

    /// filterText はユーザーが自分で打った条件なので、選択中でも一致しなければ消える。
    /// git 絞り込み(状態由来)との扱いの違いを固定する(TASK-286)。
    @Test("filterText では選択中でも一致しない行は消える")
    func filterTextDropsPresentedEntry() {
        let opened = makeEntry("README.md")
        let model = makeModel(entries: [opened, makeEntry("notes.txt")])
        model.selection = opened.id
        model.filterText = "notes*"

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["notes.txt"])
    }

    /// フォルダー移動は currentDirectory を先に進め、一覧は後から届く。その間に
    /// currentDirectory と突き合わせると「状態が別ディレクトリのもの」と判定されて
    /// 絞り込みが外れ、移動元の一覧が全件表示される(TASK-293)。突き合わせ先は
    /// 手元の一覧が由来するディレクトリ(entriesDirectory)でなければならない。
    @Test("移動先へ currentDirectory だけが進んでも、手元の一覧の絞り込みは外れない")
    func keepsFilteringWhileCurrentDirectoryRunsAhead() {
        let changed = makeEntry("changed.md")
        let model = makeModel(entries: [changed, makeEntry("clean.md")])
        applyGitStatus([changed.pathKey: modifiedStatus()], to: model)
        model.showChangedFilesOnly = true
        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])

        model.currentDirectory = URL(fileURLWithPath: "/tmp/FileListModelFilterTests/sub")

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])
    }

    /// 実測された順序(TASK-293)。`.git/index` 監視や再読込を契機とする単独の取得は、
    /// 一覧より先に移動先の状態を持ってくる。素直に入れ替えると、画面に出ている一覧
    /// (移動元)に対応する状態が失われて絞り込みが外れ、全件が一瞬表示される。
    @Test("移動先の git 状態が一覧より先に届いても、手元の一覧の絞り込みは外れない")
    func holdsIncomingStatusUntilItsEntriesArrive() {
        let changed = makeEntry("changed.md")
        let model = makeModel(entries: [])
        model.entries = [changed, makeEntry("clean.md")]
        applyGitStatus([changed.pathKey: modifiedStatus()], to: model)
        model.showChangedFilesOnly = true

        // 移動要求。一覧はまだ移動元のものが出ている。
        let next = URL(fileURLWithPath: "/tmp/FileListModelFilterTests/sub")
        model.currentDirectory = next
        let nextChanged = FileListEntry(url: next.appendingPathComponent("new.md"), kind: .file)
        applyGitStatus([nextChanged.pathKey: modifiedStatus()], to: model, directory: next)

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])

        // 一覧が届いた時点で、保留していた移動先の状態が同時に効く。
        model.entries = [nextChanged, FileListEntry(url: next.appendingPathComponent("old.md"), kind: .file)]

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["new.md"])
    }
}
