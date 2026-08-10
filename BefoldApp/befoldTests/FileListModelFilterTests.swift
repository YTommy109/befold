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
            SidebarGitStatus(repositoryRootKey: target.normalizedPathKey, statuses: statuses),
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

    /// ツリー展開では、1 つの行配列に複数階層の行が並ぶ。git 状態はリポジトリ全体ぶんの
    /// 絶対パスキーを持つので、ルートで取った 1 つの状態でどの階層も絞り込める。
    ///
    /// 突き合わせを「取得したディレクトリとの等値」へ戻すと、深い行は状態を引けず
    /// 全部消える(このテストが落ちる。TASK-361.2 の AC #4)。
    @Test("複数階層の行が、ルートで取った 1 つの状態で絞り込まれる")
    func changedFilesOnlyAppliesToRowsAtEveryDepth() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let changedDeep = FileListEntry(
            url: root.appendingPathComponent("src/nested/changed.md"), kind: .file
        )
        let cleanDeep = FileListEntry(
            url: root.appendingPathComponent("src/nested/clean.md"), kind: .file
        )
        let changedShallow = makeEntry("top.md")
        let model = makeModel(entries: [changedShallow, changedDeep, cleanDeep])
        applyGitStatus(
            [changedShallow.pathKey: modifiedStatus(), changedDeep.pathKey: modifiedStatus()],
            to: model, directory: root
        )
        model.showChangedFilesOnly = true

        #expect(
            model.visibleEntries.map(\.url.lastPathComponent) == ["top.md", "changed.md"]
        )
    }

    /// 「どの行に適用できるか」(リポジトリ包含)と「どの一覧の取得と対か」(ディレクトリ等値)は
    /// 別の判定であり、後者は緩めていない。同じリポジトリ内でも、状態が手元の一覧より
    /// 先に届いたら保留される。ここを包含へ緩めると、移動先の状態で移動元の一覧を
    /// 絞り込んで一覧が一瞬消える(TASK-293 の回帰)。
    @Test("同じリポジトリ内でも、一覧より先に届いた状態は保留される")
    func holdsStatusForAnotherDirectoryEvenWithinSameRepository() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: entries)
        let subdirectory = model.currentDirectory.appendingPathComponent("src")
        // 移動先(同じリポジトリ内のサブディレクトリ)の状態だけが先に着地した状態。
        applyGitStatus([:], to: model, directory: subdirectory)
        model.showChangedFilesOnly = true

        // 保留されているので、手元の一覧(移動元)は絞り込まれない。
        #expect(model.visibleEntries.map(\.id) == entries.map(\.id))
    }

    /// 一覧と git 状態は別タスクで届く。別リポジトリのものが残っている間は
    /// 絞り込まない(移動直後に一覧が消えるのを防ぐ)。
    @Test("状態が別リポジトリのものなら絞り込まない")
    func changedFilesOnlyIgnoresStatusFromAnotherRepository() {
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

        // 一覧が届いた時点で、保留していた移動先の状態が同時に効く。本番と同じく、
        // 列挙したディレクトリ(next)を setEntries(_:for:) で明示的に渡す。
        model.setEntries(
            [nextChanged, FileListEntry(url: next.appendingPathComponent("old.md"), kind: .file)], for: next
        )

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["new.md"])
    }

    // MARK: - setEntries(_:for:) (TASK-298)

    /// `entriesDirectory` は列挙した側(呼び出し元)が明示的に渡した値になる。
    /// `currentDirectory` が別の値を指していても、`setEntries` に渡したディレクトリが
    /// そのまま使われる(currentDirectory からの暗黙の導出に頼らない)。
    @Test("setEntries は渡されたディレクトリを entriesDirectory として使う")
    func setEntriesUsesGivenDirectoryRegardlessOfCurrentDirectory() {
        let model = makeModel(entries: [])
        let enumerated = URL(fileURLWithPath: "/tmp/FileListModelFilterTests/sub")
        let entry = FileListEntry(url: enumerated.appendingPathComponent("a.md"), kind: .file)

        model.setEntries([entry], for: enumerated)

        #expect(model.entriesDirectory == enumerated)
        #expect(model.entries.map(\.id) == [entry].map(\.id))
    }

    /// `entries` への直接代入は `entriesDirectory` を書き換えない(setEntries(_:for:) の
    /// 責務であることを固定する)。
    @Test("entries への直接代入では entriesDirectory は変わらない")
    func directEntriesAssignmentDoesNotChangeEntriesDirectory() {
        let model = makeModel(entries: [])
        let original = model.entriesDirectory
        model.currentDirectory = URL(fileURLWithPath: "/tmp/FileListModelFilterTests/sub")

        model.entries = [makeEntry("a.md")]

        #expect(model.entriesDirectory == original)
    }
}
