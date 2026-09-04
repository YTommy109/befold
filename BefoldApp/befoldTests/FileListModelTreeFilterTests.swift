@testable import befold
import Foundation
import Testing

/// ツリー展開時の絞り込みが FileListModel の導出経路へ配線されていること(TASK-361.5)。
///
/// FileListModelFilterTests から分離したのは、swiftlint の file_length /
/// type_body_length を超えないようにするため(DirectoryListerAppendingOpenFileTests と
/// 同じ理由)。純粋関数そのものは SidebarTreeFilterTests が検証する。
@Suite
@MainActor
struct FileListModelTreeFilterTests {
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

    private func modifiedStatus() -> GitFileStatus {
        GitFileStatus(indexChange: nil, worktreeChange: .modified)
    }

    /// applyGitStatus の sequence は「発行順」の連番であることが前提(ADR 0003)。
    private final class GitStatusSequence {
        private var value = 0
        func next() -> Int {
            value += 1
            return value
        }
    }

    private let gitStatusSequence = GitStatusSequence()

    private func applyGitStatus(
        _ statuses: [String: GitFileStatus], to model: FileListModel, directory: URL? = nil
    ) {
        let target = directory ?? model.currentDirectory
        model.applyGitStatus(
            SidebarGitStatus(repositoryRootKey: target.normalizedPathKey, statuses: statuses),
            for: target, sequence: gitStatusSequence.next()
        )
    }

    /// 純粋関数(SidebarTreeFilter)のテストだけでは、visibleEntries へ実際に
    /// 配線されたかが測れない。ここで本番の導出経路を通す。
    @Test("ツリー展開時、名前フィルタに一致した子の祖先フォルダが残る")
    func treeFilterKeepsAncestorsOfMatchingRows() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let dirA = FileListEntry(url: root.appendingPathComponent("src"), kind: .folder)
        let nested = FileListEntry(
            url: root.appendingPathComponent("src/note.md"), kind: .file
        )
        let model = makeModel(entries: [])
        model.entries = SidebarRowBuilder.rows(
            rootChildren: [dirA, makeEntry("other.txt")],
            expanded: [dirA.pathKey],
            childrenByPathKey: [dirA.pathKey: [nested]],
            showsDisclosure: true
        )
        model.transient.filterText = "note*"

        // 親フォルダ "src" は "note*" に一致しないが、子が残るので一緒に残る。
        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["src", "note.md"])
        #expect(model.visibleEntries.map(\.depth) == [0, 1])
    }

    /// TASK-403 のもう 1 つの到達経路。親を表示したままサブモジュール配下の行が
    /// 並ぶため、境界配下を残す例外が祖先の足し戻しまで届くことを本番の導出経路で確かめる。
    @Test("変更のみ表示 ON でも、ツリー展開したサブモジュール配下と祖先が残る")
    func treeFilterKeepsSubmoduleDescendantsAndAncestors() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let submodule = FileListEntry(url: root.appendingPathComponent("sub"), kind: .folder)
        let inner = FileListEntry(url: root.appendingPathComponent("sub/a.txt"), kind: .file)
        let model = makeModel(entries: [])
        model.entries = SidebarRowBuilder.rows(
            rootChildren: [submodule, makeEntry("clean.txt")],
            expanded: [submodule.pathKey],
            childrenByPathKey: [submodule.pathKey: [inner]],
            showsDisclosure: true
        )
        model.applyGitStatus(
            SidebarGitStatus(
                repositoryRootKey: root.normalizedPathKey,
                statuses: [submodule.pathKey: modifiedStatus()],
                indeterminateRoots: [submodule.pathKey]
            ),
            for: root, sequence: gitStatusSequence.next()
        )
        model.showChangedFilesOnly = true

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["sub", "a.txt"])
    }

    /// 祖先として残った行は、定義上 1 つ以上の子が見えているので `.expanded` のまま。
    @Test("祖先として残ったフォルダの開閉三角は展開のまま")
    func ancestorKeptByFilterStaysExpanded() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let dirA = FileListEntry(url: root.appendingPathComponent("src"), kind: .folder)
        let nested = FileListEntry(url: root.appendingPathComponent("src/note.md"), kind: .file)
        let model = makeModel(entries: [])
        model.entries = SidebarRowBuilder.rows(
            rootChildren: [dirA],
            expanded: [dirA.pathKey],
            childrenByPathKey: [dirA.pathKey: [nested]],
            showsDisclosure: true
        )
        model.transient.filterText = "note*"

        #expect(model.visibleEntries.first?.disclosure == .expanded)
    }

    // MARK: - フォルダー移動直後の初期選択(task-406)

    /// 祖先として残っただけのフォルダは、見えていても初期選択にしない。ここを
    /// 「見えている先頭」に戻すと、絞り込み中にフォルダを降りた利用者は毎回
    /// 一致行まで矢印キーで降りることになる。
    @Test("ツリー表示 + 名前フィルタでは、祖先が先頭でも一致した行が初期選択になる")
    func firstSelectableEntrySkipsAncestorsKeptByFilter() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let dirA = FileListEntry(url: root.appendingPathComponent("src"), kind: .folder)
        let nested = FileListEntry(url: root.appendingPathComponent("src/note.md"), kind: .file)
        let model = makeModel(entries: [])
        model.entries = SidebarRowBuilder.rows(
            rootChildren: [dirA],
            expanded: [dirA.pathKey],
            childrenByPathKey: [dirA.pathKey: [nested]],
            showsDisclosure: true
        )
        model.transient.filterText = "note*"

        // 見えている先頭は "src"(一致していない祖先)。
        #expect(model.visibleEntries.first?.url == dirA.url)
        #expect(model.firstSelectableEntryURL == nested.url)
    }

    /// 一致行の優先が「祖先を常に飛ばす」形へ退化していないこと。絞り込みが無ければ
    /// 全行が一致行なので、従来どおり見えている先頭を採る。
    @Test("絞り込みが無ければ、初期選択は見えている先頭のまま")
    func firstSelectableEntryPrefersVisibleHeadWithoutFilter() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let dirA = FileListEntry(url: root.appendingPathComponent("src"), kind: .folder)
        let nested = FileListEntry(url: root.appendingPathComponent("src/note.md"), kind: .file)
        let model = makeModel(entries: [])
        model.entries = SidebarRowBuilder.rows(
            rootChildren: [dirA], expanded: [dirA.pathKey],
            childrenByPathKey: [dirA.pathKey: [nested]], showsDisclosure: true
        )

        #expect(model.firstSelectableEntryURL == dirA.url)
    }

    /// 一致が 1 つも無ければ祖先も残らない。祖先保持が「常に全フォルダを残す」形に
    /// 退化していないことを押さえる。
    @Test("一致が 1 つも無ければ、祖先フォルダも残らない")
    func treeFilterDropsEverythingWhenNothingMatches() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let dirA = FileListEntry(url: root.appendingPathComponent("src"), kind: .folder)
        let nested = FileListEntry(url: root.appendingPathComponent("src/note.md"), kind: .file)
        let model = makeModel(entries: [])
        model.entries = SidebarRowBuilder.rows(
            rootChildren: [dirA],
            expanded: [dirA.pathKey],
            childrenByPathKey: [dirA.pathKey: [nested]],
            showsDisclosure: true
        )
        model.transient.filterText = "nomatch*"

        #expect(model.visibleEntries.isEmpty)
    }

    /// プレビューへ渡す一覧は祖先を足し戻す**前**から採る。足し戻した配列を渡すと、
    /// 条件に一致しないフォルダがプレビューにも現れ、1 ウィンドウ内に絞り込みの
    /// 答えが 2 つ並ぶ(TASK-288 の巻き戻し)。
    @Test("プレビューへ渡す一覧には、祖先として残したフォルダを含めない")
    func listingSourceExcludesAncestorsKeptByFilter() {
        let root = URL(fileURLWithPath: "/tmp/FileListModelFilterTests")
        let dirA = FileListEntry(url: root.appendingPathComponent("src"), kind: .folder)
        let nested = FileListEntry(url: root.appendingPathComponent("src/note.md"), kind: .file)
        let model = makeModel(entries: [])
        model.entries = SidebarRowBuilder.rows(
            rootChildren: [dirA],
            expanded: [dirA.pathKey],
            childrenByPathKey: [dirA.pathKey: [nested]],
            showsDisclosure: true
        )
        model.transient.filterText = "note*"

        guard case let .shared(shared) = model.listingSource(for: model.currentDirectory) else {
            Issue.record("listingSource が .shared ではない")
            return
        }
        #expect(shared?.entries.isEmpty == true)
        // サイドバー側には祖先が残っている（両者で答えが違うのは意図した設計）。
        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["src", "note.md"])
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
        model.transient.filterText = "notes*"

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
        // 列挙したディレクトリ(next)を setEntries で明示的に渡す。
        model.setEntries(
            [nextChanged, FileListEntry(url: next.appendingPathComponent("old.md"), kind: .file)],
            for: next, didFailEnumeration: false
        )

        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["new.md"])
    }

    // MARK: - setEntries (TASK-298)

    /// `entriesDirectory` は列挙した側(呼び出し元)が明示的に渡した値になる。
    /// `currentDirectory` が別の値を指していても、`setEntries` に渡したディレクトリが
    /// そのまま使われる(currentDirectory からの暗黙の導出に頼らない)。
    @Test("setEntries は渡されたディレクトリを entriesDirectory として使う")
    func setEntriesUsesGivenDirectoryRegardlessOfCurrentDirectory() {
        let model = makeModel(entries: [])
        let enumerated = URL(fileURLWithPath: "/tmp/FileListModelFilterTests/sub")
        let entry = FileListEntry(url: enumerated.appendingPathComponent("a.md"), kind: .file)

        model.setEntries([entry], for: enumerated, didFailEnumeration: false)

        #expect(model.entriesDirectory == enumerated)
        #expect(model.entries.map(\.id) == [entry].map(\.id))
    }

    /// `entries` への直接代入は `entriesDirectory` を書き換えない(setEntries の
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
