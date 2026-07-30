import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// git リポジトリのファイルを開く/ウィンドウを閉じる操作が RecentRepositoriesStore に
/// 正しく反映されることを検証する。実 git は起動せず、gitFileIndex を
/// RecordingGitFileIndex 派生のフェイクへ差し替えて root 解決を固定する。
@Suite
@MainActor
struct ViewerWindowManagerRecentRepositoriesTests {
    /// 常に固定の root を返すフェイク。実 git を起動しない。
    private final class FixedRootGitFileIndex: GitFileIndexing, @unchecked Sendable {
        let root: URL?
        init(root: URL?) {
            self.root = root
        }

        func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
            nil
        }

        func repositoryRoot(forFileAt _: URL) -> URL? {
            root
        }

        func warm(forFileAt _: URL) {}
    }

    private func makeManager(
        files: [URL], root: URL?, defaults: UserDefaults
    ) -> (manager: ViewerWindowManager, recentRepositoriesStore: RecentRepositoriesStore) {
        let fileReader = InMemoryFileReader(
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.path, "graph TD;") })
        )
        let sessionStore = SessionStore(defaults: defaults)
        let recentDocumentsStore = RecentDocumentsStore(defaults: defaults)
        let recentRepositoriesStore = RecentRepositoriesStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            fileReader: fileReader,
            makeStore: { _ in
                ViewerStore(
                    watcherFactory: { _, _, _ in MockFileWatcher() },
                    fileReader: fileReader,
                    defaults: defaults
                )
            },
            directoryLister: { _, _, _ in [] },
            gitFileIndex: FixedRootGitFileIndex(root: root),
            recentRepositoriesStore: recentRepositoriesStore
        )
        return (manager, recentRepositoriesStore)
    }

    @Test("git リポジトリ内のファイルを開くと最近使ったリポジトリに記録される")
    func openingFileInsideRepositoryRecordsIt() {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/repo/a.md")
        let root = URL(fileURLWithPath: "/repo")
        let (manager, store) = makeManager(files: [file], root: root, defaults: defaults)

        manager.openViewer(for: file)

        #expect(store.entries().map(\.rootPath) == [root.normalizedPathKey])
        #expect(manager.controllers[file.normalizedPathKey]?.first?.repositoryRoot == root)
        manager.allControllers.forEach { $0.close() }
    }

    @Test("git 管理外のファイルを開いても記録されない")
    func openingFileOutsideRepositoryDoesNotRecordAnything() {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/standalone/a.md")
        let (manager, store) = makeManager(files: [file], root: nil, defaults: defaults)

        manager.openViewer(for: file)

        #expect(store.entries().isEmpty)
        #expect(manager.controllers[file.normalizedPathKey]?.first?.repositoryRoot == nil)
        manager.allControllers.forEach { $0.close() }
    }

    @Test("リポジトリのウィンドウを閉じるとタブ構成が記録される")
    func closingWindowRecordsLastTabGroup() throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/repo/a.md")
        let root = URL(fileURLWithPath: "/repo")
        let (manager, store) = makeManager(files: [file], root: root, defaults: defaults)
        manager.openViewer(for: file)
        let controller = try #require(manager.controllers[file.normalizedPathKey]?.first)

        controller.close()

        let saved = store.entries().first { $0.rootPath == root.normalizedPathKey }
        #expect(saved?.lastTabGroup?.paths == [file.normalizedPathKey])
        #expect(saved?.lastTabGroup?.selectedPath == file.normalizedPathKey)
    }
}
