@testable import befold
import Foundation
import Testing

/// フォルダー一覧ヘッダーの項目数(TASK-706)。数えるのは絞り込み後の「見えている行」。
@Suite
@MainActor
struct FolderListingItemCountTests {
    private let directory = URL(fileURLWithPath: "/tmp/FolderListingItemCountTests")

    private func makeEntry(_ name: String, kind: FileListEntry.Kind = .file) -> FileListEntry {
        FileListEntry(url: directory.appendingPathComponent(name), kind: kind)
    }

    private func makeView(
        filter: FileListFilter, entries: [FileListEntry]?, didFail: Bool = false
    ) -> FolderListingView {
        FolderListingView(
            directory: directory,
            sortOrder: .foldersFirst,
            showHiddenFiles: false,
            filter: filter,
            source: .shared(entries.map { SharedFolderListing(entries: $0, didFailEnumeration: didFail) }),
            openFile: nil,
            onSelectFile: { _ in },
            onNavigateToFolder: { _ in }
        )
    }

    @Test("項目数は絞り込み後の見えている行を数え、実数ではない")
    func countsVisibleRowsNotDiskTotal() {
        let changed = makeEntry("changed.md")
        let entries = [changed, makeEntry("clean.md"), makeEntry("sub", kind: .folder)]
        let model = FileListModel(currentDirectory: directory, entries: entries, selection: nil)
        let unfiltered = makeView(filter: model.listFilter, entries: entries)
        #expect(unfiltered.itemCountHeader?.contains("3") == true)
        // 未解決のプレースホルダ(%lld)が残っていない=複数形の解決まで通っている
        #expect(unfiltered.itemCountHeader?.contains("%") == false)

        model.applyGitStatus(
            SidebarGitStatus(
                repositoryRootKey: directory.normalizedPathKey,
                statuses: [changed.pathKey: GitFileStatus(indexChange: nil, worktreeChange: .modified)]
            ),
            for: directory, sequence: 1
        )
        model.display.apply(.toggleChangedFilesOnly)
        // .shared は絞り込み済みの一覧が渡る(FolderListingSourceResolver)ので同じ形で渡す
        let filtered = makeView(
            filter: model.listFilter, entries: model.listFilter.apply(to: entries, in: directory)
        )
        #expect(filtered.itemCountHeader?.contains("1") == true)
    }

    @Test("一覧が未到着ならヘッダーは出ず、列挙失敗は項目数でなく失敗を示す")
    func pendingAndFailure() {
        let filter = FileListModel(currentDirectory: directory, entries: [], selection: nil).listFilter
        #expect(makeView(filter: filter, entries: nil).itemCountHeader == nil)

        let failed = makeView(filter: filter, entries: [], didFail: true).itemCountHeader
        let empty = makeView(filter: filter, entries: []).itemCountHeader
        #expect(failed != nil)
        #expect(failed != empty)
    }
}
