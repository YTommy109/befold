@testable import befold
import Foundation
import Testing

/// フォルダープレビューの一覧がサイドバーと同じ絞り込みに従うことの回帰テスト(TASK-288)。
///
/// 以前はプレビュー側へ sortOrder と showHiddenFiles しか渡っておらず、「変更のみ表示」が
/// サイドバーにしか効かなかった。1 ウィンドウ内に 2 つの答えが並ばないことを、
/// サイドバー(FileListModel.visibleEntries)との一致で確かめる。
@Suite
@MainActor
struct FolderListingViewFilterTests {
    private let directory = URL(fileURLWithPath: "/tmp/FolderListingViewFilterTests")

    private func makeEntry(_ name: String, kind: FileListEntry.Kind = .file) -> FileListEntry {
        FileListEntry(url: directory.appendingPathComponent(name), kind: kind)
    }

    private func makeModel(entries: [FileListEntry]) -> FileListModel {
        FileListModel(currentDirectory: directory, entries: entries, selection: nil)
    }

    private func makeView(
        directory: URL, filter: FileListFilter,
        source: FolderListingSource = .ownListing, openFile: URL? = nil
    ) -> FolderListingView {
        FolderListingView(
            directory: directory,
            sortOrder: .foldersFirst,
            showHiddenFiles: false,
            filter: filter,
            source: source,
            openFile: openFile,
            onSelectFile: { _ in },
            onNavigateToFolder: { _ in }
        )
    }

    private func modifiedStatus() -> GitFileStatus {
        GitFileStatus(indexChange: nil, worktreeChange: .modified)
    }

    @Test("変更のみ表示 ON のとき、プレビュー一覧からも未変更ファイルが消える")
    func changedFilesOnlyAppliesToPreview() {
        let changed = makeEntry("changed.md")
        let entries = [changed, makeEntry("clean.md")]
        let model = makeModel(entries: entries)
        model.applyGitStatus(
            SidebarGitStatus(directoryKey: directory.normalizedPathKey, statuses: [changed.pathKey: modifiedStatus()]),
            for: directory
        )
        model.showChangedFilesOnly = true

        let view = makeView(directory: directory, filter: model.listFilter)

        #expect(view.visibleEntries(from: entries).map(\.url.lastPathComponent) == ["changed.md"])
    }

    @Test("表示中ディレクトリを提示しているとき、プレビュー一覧はサイドバーと完全に一致する")
    func previewMatchesSidebarForCurrentDirectory() {
        let changed = makeEntry("changed.md")
        let folder = makeEntry("src", kind: .folder)
        let entries = [
            makeEntry("..", kind: .parentNavigation), folder, changed, makeEntry("clean.md"),
        ]
        let model = makeModel(entries: entries)
        let nested = folder.url.appendingPathComponent("inner.md").normalizedPathKey
        model.applyGitStatus(
            SidebarGitStatus(
                directoryKey: directory.normalizedPathKey,
                statuses: [changed.pathKey: modifiedStatus(), nested: modifiedStatus()]
            ),
            for: directory
        )
        model.showChangedFilesOnly = true
        model.filterText = "*.md"

        let view = makeView(directory: model.currentDirectory, filter: model.listFilter)

        #expect(view.visibleEntries(from: entries).map(\.id) == model.visibleEntries.map(\.id))
        #expect(model.visibleEntries.map(\.url.lastPathComponent) == ["..", "changed.md"])
    }

    @Test("絞り込み OFF ならプレビュー一覧は取得した全件をそのまま出す")
    func noFilterKeepsEveryEntry() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: entries)

        let view = makeView(directory: directory, filter: model.listFilter)

        #expect(view.visibleEntries(from: entries).map(\.id) == entries.map(\.id))
    }

    @Test("選択中のサブフォルダーを提示しているときは、別ディレクトリの git 絞り込みが効かない")
    func gitFilterDoesNotApplyToSubfolderListing() {
        let folder = makeEntry("src", kind: .folder)
        let model = makeModel(entries: [folder])
        let child = folder.url.appendingPathComponent("inner.md")
        let sibling = folder.url.appendingPathComponent("untouched.md")
        // 状態は表示中ディレクトリのもの。サブフォルダー配下の行とは突き合わせられないため、
        // ここで絞り込むと一覧が丸ごと消える。
        model.applyGitStatus(
            SidebarGitStatus(
                directoryKey: directory.normalizedPathKey,
                statuses: [child.normalizedPathKey: modifiedStatus()]
            ),
            for: directory
        )
        model.showChangedFilesOnly = true

        let childEntries = [
            FileListEntry(url: child, kind: .file), FileListEntry(url: sibling, kind: .file),
        ]
        let view = makeView(directory: folder.url, filter: model.listFilter)

        #expect(
            view.visibleEntries(from: childEntries).map(\.url.lastPathComponent)
                == ["inner.md", "untouched.md"]
        )
    }

    // MARK: - Listing Source (TASK-293)

    /// 表示中ディレクトリのプレビューは自前で列挙してはいけない。列挙と git 状態の完了順が
    /// 揃わず、絞り込みが効く前の全件が一瞬描画される。サイドバーが git 状態と一緒に
    /// 揃えた一覧をそのまま使う。
    @Test("表示中ディレクトリのプレビューはサイドバーの一覧をそのまま使う")
    func usesSidebarEntriesForCurrentDirectory() {
        let entries = [makeEntry("a.md"), makeEntry("b.md")]
        let model = makeModel(entries: [])
        // ウィンドウは一覧を空で作って非同期に埋める。本番と同じ経路で入れる。
        model.entries = entries

        #expect(model.listingSource(for: directory) == .shared(entries))
    }

    /// 移動要求で currentDirectory だけが先に進んでいる間は「まだ手元に無い」を返す。
    /// ここで移動元の一覧を渡すと、別フォルダーの中身が一瞬見えることになる。
    /// git 絞り込みが ON の間は、対になる git 状態が届くまで待たせる必要がある。
    @Test("絞り込み ON なら、一覧が届く前は表示中ディレクトリのプレビューへ何も渡さない")
    func sharesNothingBeforeEntriesArrive() {
        let model = makeModel(entries: [])
        model.showChangedFilesOnly = true
        model.entries = [makeEntry("a.md")]
        let next = directory.appendingPathComponent("sub", isDirectory: true)
        model.currentDirectory = next

        #expect(model.listingSource(for: next) == .shared(nil))
    }

    /// 絞り込みが OFF なら対にすべき git 状態が無いので待つ理由がない。待たせると
    /// プレビュー中のサブフォルダーへ移動した瞬間に一覧が空へ落ちる(TASK-295)。
    @Test("絞り込み OFF なら、一覧が届く前のプレビューは自前で列挙する")
    func fallsBackToOwnListingWhileWaitingWithoutGitFilter() {
        let model = makeModel(entries: [])
        model.entries = [makeEntry("a.md")]
        let next = directory.appendingPathComponent("sub", isDirectory: true)
        model.currentDirectory = next

        #expect(model.listingSource(for: next) == .ownListing)
    }

    /// 選択中のサブフォルダーは手元に一覧が無いので自前で列挙させる。
    /// そちらは git 状態の対象外であり、絞り込み自体が働かない。
    @Test("選択中のサブフォルダーのプレビューは自前で列挙する")
    func usesOwnListingForSubfolder() {
        let model = makeModel(entries: [makeEntry("src", kind: .folder)])

        #expect(model.listingSource(for: directory.appendingPathComponent("src")) == .ownListing)
    }

    // MARK: - Source Switching (TASK-295)

    /// `.shared(nil)` は「git 状態と対になった一覧を待て」の意味。手元の自前列挙へ退避すると、
    /// 絞り込み前の全件が一瞬描画され(TASK-293 の回帰)、列挙し直さないため削除済みの
    /// ファイルも残る。待たなくてよい場面では供給元自体が `.ownListing` になる(TASK-301)。
    @Test("一覧の到着待ちでは、自前列挙のキャッシュへ退避しない")
    func doesNotFallBackToCachedEntriesWhileWaiting() {
        let cached = [makeEntry("a.md"), makeEntry("b.md")]

        #expect(FolderListingView.resolveEntries(source: .shared(nil), cached: cached) == nil)
    }

    /// サイドバーの一覧が届いたらそちらが優先される(git 状態と揃った一覧はこちらだけ)。
    @Test("サイドバーの一覧が届いたら自前の列挙より優先する")
    func sharedEntriesWinOverOwnListing() {
        let shared = [makeEntry("shared.md")]

        let resolved = FolderListingView.resolveEntries(
            source: .shared(shared), cached: [makeEntry("stale.md")]
        )

        #expect(resolved?.map(\.url.lastPathComponent) == ["shared.md"])
    }

    /// 手元に何も無ければ「未取得」のまま。空一覧と取り違えると空状態の文言が先に出る。
    @Test("供給元も自前列挙も無ければ未取得のまま")
    func staysUnloadedWithoutAnyEntries() {
        #expect(FolderListingView.resolveEntries(source: .shared(nil), cached: nil) == nil)
    }

    /// ディレクトリが据え置きのまま .shared → .ownListing へ切り替わることがある。
    /// 再取得のキーが変わらないと列挙が一度も走らず、プレビューが恒久的に空になる。
    @Test("供給元が切り替わったら、ディレクトリが同じでも一覧を取り直す")
    func listingKeyChangesWhenSourceSwitches() {
        let filter = FileListFilter()
        let shared = makeView(directory: directory, filter: filter, source: .shared([]))
        let own = makeView(directory: directory, filter: filter, source: .ownListing)

        #expect(shared.listingKey != own.listingKey)
    }

    // MARK: - Open File (TASK-295)

    /// 列挙に載らない拡張子のファイルを開いていると、サイドバーだけが末尾へ足していた。
    /// 同じフォルダーでも見る経路によって中身が食い違わないよう、プレビューも同じ規則を通す。
    @Test("開いているファイルは、どちらの供給元から見ても一覧に現れる")
    func openFileAppearsRegardlessOfSource() {
        let openFile = directory.appendingPathComponent("notes.xyz")
        let listed = [makeEntry("a.md")]
        let view = makeView(
            directory: directory, filter: FileListFilter(), openFile: openFile
        )

        #expect(
            view.visibleEntries(from: listed).map(\.url.lastPathComponent) == ["a.md", "notes.xyz"]
        )
    }

    /// サイドバーの一覧には既に入っているため、二重に足してはならない。
    @Test("開いているファイルが既に一覧にあれば重複させない")
    func openFileIsNotDuplicated() {
        let openFile = directory.appendingPathComponent("a.md")
        let listed = [makeEntry("a.md")]
        let view = makeView(
            directory: directory, filter: FileListFilter(), source: .shared(listed),
            openFile: openFile
        )

        #expect(view.visibleEntries(from: listed).map(\.url.lastPathComponent) == ["a.md"])
    }

    /// 一覧がまだ手元に無い間に「開いているファイル」を足すと、本来ブランクであるべき
    /// 読み込み中に 1 行だけの幻リストが出て、全件一覧へ差し替わる形でチラつく(TASK-301)。
    @Test("一覧の到着待ちでは、開いているファイル 1 行だけのリストを出さない")
    func showsNothingWhileWaitingEvenWithOpenFile() {
        let openFile = directory.appendingPathComponent("notes.xyz")
        let view = makeView(
            directory: directory, filter: FileListFilter(), source: .shared(nil),
            openFile: openFile
        )

        #expect(view.displayedEntries == nil)
    }

    /// 別フォルダーのファイルを開いているときに、その行がここへ現れてはならない。
    @Test("別フォルダーのファイルを開いていても一覧には足さない")
    func openFileOutsideDirectoryIsIgnored() {
        let openFile = directory.appendingPathComponent("src/inner.xyz")
        let listed = [makeEntry("a.md")]
        let view = makeView(
            directory: directory, filter: FileListFilter(), openFile: openFile
        )

        #expect(view.visibleEntries(from: listed).map(\.url.lastPathComponent) == ["a.md"])
    }
}
