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
        directory: URL, filter: FileListFilter
    ) -> FolderListingView {
        FolderListingView(
            directory: directory,
            sortOrder: .foldersFirst,
            showHiddenFiles: false,
            filter: filter,
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
        model.gitStatus = SidebarGitStatus(
            directoryKey: directory.normalizedPathKey, statuses: [changed.pathKey: modifiedStatus()]
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
        model.gitStatus = SidebarGitStatus(
            directoryKey: directory.normalizedPathKey,
            statuses: [changed.pathKey: modifiedStatus(), nested: modifiedStatus()]
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
        model.gitStatus = SidebarGitStatus(
            directoryKey: directory.normalizedPathKey,
            statuses: [child.normalizedPathKey: modifiedStatus()]
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
}
