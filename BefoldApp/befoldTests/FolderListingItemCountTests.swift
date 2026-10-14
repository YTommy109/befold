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

/// 複数形の解決(en は 1 件だけ単数、ja は常に同じ形)。
struct FolderListingPluralTests {
    @Test("項目数の複数形がカタログに en/ja の複数形が揃っている")
    func pluralVariationsResolve() throws {
        // SPM のテストはカタログをコンパイルせず実行時の複数形を引けないため、カタログの形を読む
        // (コンパイル後の stringsdict は xcodebuild の成果物で確認済み)。
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("befold/Resources/Localizable.xcstrings")
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        )
        let strings = try #require(json["strings"] as? [String: Any])
        let entry = try #require(strings["folderListing.itemCount %lld"] as? [String: Any])
        let locs = try #require(entry["localizations"] as? [String: [String: Any]])
        func categories(_ lang: String) -> Set<String> {
            let plural = (locs[lang]?["variations"] as? [String: Any])?["plural"] as? [String: Any]
            return Set(plural?.keys.map(\.self) ?? [])
        }
        #expect(categories("en") == ["one", "other"])
        #expect(categories("ja") == ["other"])
    }
}
