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
}
