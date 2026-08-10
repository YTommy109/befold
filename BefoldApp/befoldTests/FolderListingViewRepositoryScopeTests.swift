@testable import befold
import Foundation
import Testing

/// git 絞り込みの適用範囲がリポジトリ単位であることの回帰テスト(TASK-361.2)。
///
/// FolderListingViewFilterTests から分離したのは、swiftlint の type_body_length を
/// 超えないようにするため(DirectoryListerAppendingOpenFileTests と同じ理由)。
@Suite
@MainActor
struct FolderListingViewRepositoryScopeTests {
    private let directory = URL(fileURLWithPath: "/tmp/FolderListingViewRepositoryScopeTests")

    private func makeEntry(_ name: String, kind: FileListEntry.Kind = .file) -> FileListEntry {
        FileListEntry(url: directory.appendingPathComponent(name), kind: kind)
    }

    private func makeModel(entries: [FileListEntry]) -> FileListModel {
        FileListModel(currentDirectory: directory, entries: entries, selection: nil)
    }

    private func makeView(directory: URL, filter: FileListFilter) -> FolderListingView {
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

    /// git 状態はリポジトリ全体ぶんの絶対パスキーを持つため、サブフォルダー配下の行とも
    /// 突き合わせられる。サイドバーとプレビューで絞り込みの答えを 1 つにする(TASK-288)
    /// 方針どおり、同じリポジトリ内なら同じ絞り込みが効く。
    ///
    /// 以前は取得したディレクトリとの**等値**で突き合わせており、ここだけ絞り込みが
    /// 外れていた。等値へ戻すとこのテストが落ちる(TASK-361.2)。
    @Test("選択中のサブフォルダーのプレビューにも、同じリポジトリの git 絞り込みが効く")
    func gitFilterAppliesToSubfolderListingInSameRepository() {
        let folder = makeEntry("src", kind: .folder)
        let model = makeModel(entries: [folder])
        let child = folder.url.appendingPathComponent("inner.md")
        let sibling = folder.url.appendingPathComponent("untouched.md")
        model.applyGitStatus(
            SidebarGitStatus(
                repositoryRootKey: directory.normalizedPathKey,
                statuses: [child.normalizedPathKey: modifiedStatus()]
            ),
            for: directory, sequence: 1
        )
        model.showChangedFilesOnly = true

        let childEntries = [
            FileListEntry(url: child, kind: .file), FileListEntry(url: sibling, kind: .file),
        ]
        let view = makeView(directory: folder.url, filter: model.listFilter)

        #expect(view.visibleEntries(from: childEntries).map(\.url.lastPathComponent) == ["inner.md"])
    }

    /// 別リポジトリの状態では絞り込まない。前方一致だけで判定すると、ルートが
    /// `/tmp/x` のときの `/tmp/x2` のような兄弟パスが誤って配下と見なされる。
    @Test("兄弟パスの別リポジトリの git 絞り込みは効かない")
    func gitFilterDoesNotApplyAcrossSiblingRepositories() {
        let folder = makeEntry("src", kind: .folder)
        let model = makeModel(entries: [folder])
        let child = folder.url.appendingPathComponent("inner.md")
        let sibling = folder.url.appendingPathComponent("untouched.md")
        let otherRepository = URL(fileURLWithPath: directory.path + "2")
        model.applyGitStatus(
            SidebarGitStatus(
                repositoryRootKey: otherRepository.normalizedPathKey,
                statuses: [child.normalizedPathKey: modifiedStatus()]
            ),
            for: directory, sequence: 1
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

    /// 祖先保持はサイドバー専用で、プレビュー内のフォルダー一覧には入れない。
    /// あちらは 1 階層ぶんのフラットな一覧しか持たず、祖先の概念が無い。
    /// FileListFilter(両者が共有する型)へ祖先保持を持ち込むと、この境界が壊れる。
    @Test("プレビューの一覧では、深さを持つ行を渡しても祖先が足し戻されない")
    func previewListingDoesNotKeepAncestors() {
        let model = makeModel(entries: [])
        model.filterText = "note*"
        let dirA = makeEntry("src", kind: .folder)
        let nested = FileListEntry(url: dirA.url.appendingPathComponent("note.md"), kind: .file)
        let view = makeView(directory: directory, filter: model.listFilter)

        // 祖先保持が FileListFilter 側へ入っていれば "src" も残ってしまう。
        let rows = [dirA, nested.indented(to: 1)]
        #expect(view.visibleEntries(from: rows).map(\.url.lastPathComponent) == ["note.md"])
    }

    /// TASK-361.1 で FileListEntry の等値から depth を外した前提の固定。
    /// FolderListingSource は Equatable で `case shared([FileListEntry]?)` を持つため、
    /// 合成の等値へ戻すと深さの違いだけで別物と判定される。
    @Test("FolderListingSource の比較は行の depth の違いで別物にならない")
    func sharedSourceEqualityIgnoresDepth() {
        let entry = makeEntry("a.md", kind: .file)

        #expect(FolderListingSource.shared([entry]) == .shared([entry.indented(to: 2)]))
        #expect(FolderListingSource.shared([entry]) != .ownListing)
    }
}
