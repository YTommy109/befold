import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// git リポジトリのファイルを開く/ウィンドウを閉じる操作が RecentRepositoriesStore に
/// 正しく反映されることを検証する。実 git は起動せず、gitFileIndex を
/// RecordingGitFileIndex 派生のフェイクへ差し替えて root 解決を固定する。
///
/// 記録は detached タスクで解決してから MainActor へ戻るため、openViewer 直後には
/// まだ反映されていない。各テストは反映(repositoryRoot / entries)を待ってから検証する。
@Suite
@MainActor
struct ViewerWindowManagerRecentRepositoriesTests {
    /// 常に固定の root を返すフェイク。実 git を起動しない。
    /// root 解決の呼び出し回数を数えられるようにして、「何も記録されない」ことの検証で
    /// 解決が済んだ後に判定できるようにする。
    private final class FixedRootGitFileIndex: GitFileIndexing, @unchecked Sendable {
        let root: URL?
        let rootLookupCount = LockedBox(0)

        init(root: URL?) {
            self.root = root
        }

        func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
            nil
        }

        func repositoryRoot(forFileAt _: URL) -> URL? {
            rootLookupCount.update { $0 += 1 }
            return root
        }

        func warm(forFileAt _: URL) {}
    }

    private struct Fixture {
        let manager: ViewerWindowManager
        let store: RecentRepositoriesStore
        let gitFileIndex: FixedRootGitFileIndex
    }

    private func makeFixture(files: [URL], root: URL?, defaults: UserDefaults) -> Fixture {
        let fileReader = InMemoryFileReader(
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.path, "graph TD;") })
        )
        let sessionStore = SessionStore(defaults: defaults)
        let recentDocumentsStore = RecentDocumentsStore(defaults: defaults)
        let recentRepositoriesStore = RecentRepositoriesStore(defaults: defaults)
        let gitFileIndex = FixedRootGitFileIndex(root: root)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            fileReader: fileReader,
            makeStore: { _ in
                ViewerStore(
                    watcherFactory: { _, _, _, _ in MockFileWatcher() },
                    fileReader: fileReader,
                    defaults: defaults
                )
            },
            gitFileIndex: gitFileIndex,
            recentRepositoriesStore: recentRepositoriesStore,
            repositoryIdentityResolver: {
                RepositoryIdentity(label: $0.lastPathComponent, mainRoot: $0)
            }
        )
        return Fixture(manager: manager, store: recentRepositoriesStore, gitFileIndex: gitFileIndex)
    }

    /// 指定ファイルのウィンドウを開き、非同期の git 解決が反映されるまで待って返す。
    private func openAndAwaitRecording(
        _ fixture: Fixture, file: URL, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> ViewerWindowController {
        fixture.manager.openViewer(for: file)
        let controller = try #require(
            fixture.manager.controllers[file.normalizedPathKey]?.first, sourceLocation: sourceLocation
        )
        await waitUntilOnMainActor(sourceLocation: sourceLocation) { controller.repositoryRoot != nil }
        return controller
    }

    @Test("git リポジトリ内のファイルを開くと最近使ったリポジトリに記録される")
    func openingFileInsideRepositoryRecordsIt() async throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/repo/a.md")
        let root = URL(fileURLWithPath: "/repo")
        let fixture = makeFixture(files: [file], root: root, defaults: defaults)

        let controller = try await openAndAwaitRecording(fixture, file: file)

        #expect(fixture.store.entries().map(\.rootPath) == [root.normalizedPathKey])
        #expect(controller.repositoryRoot == root)
        fixture.manager.allControllers.forEach { $0.close() }
    }

    @Test("git 管理外のファイルを開いても記録されない")
    func openingFileOutsideRepositoryDoesNotRecordAnything() async {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/standalone/a.md")
        let fixture = makeFixture(files: [file], root: nil, defaults: defaults)

        fixture.manager.openViewer(for: file)

        // root が nil と分かった時点で記録経路は打ち切られる。解決が済んだことを
        // 待ってから判定することで、「まだ走っていないだけ」の空を成功と誤認しない。
        let index = fixture.gitFileIndex
        await waitUntil { index.rootLookupCount.get() > 0 }
        #expect(fixture.store.entries().isEmpty)
        #expect(fixture.manager.controllers[file.normalizedPathKey]?.first?.repositoryRoot == nil)
        fixture.manager.allControllers.forEach { $0.close() }
    }

    @Test("リポジトリのウィンドウを閉じるとタブ構成が記録される")
    func closingWindowRecordsLastTabGroup() async throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/repo/a.md")
        let root = URL(fileURLWithPath: "/repo")
        let fixture = makeFixture(files: [file], root: root, defaults: defaults)
        let controller = try await openAndAwaitRecording(fixture, file: file)

        controller.close()

        let saved = fixture.store.entries().first { $0.rootPath == root.normalizedPathKey }
        #expect(saved?.lastTabGroup?.paths == [file.normalizedPathKey])
        #expect(saved?.lastTabGroup?.selectedPath == file.normalizedPathKey)
    }

    @Test("アクティブ化でタブ構成が記録され、1枚ずつ閉じても縮まない")
    func closingTabsOneByOneKeepsFullTabGroup() async throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let fileB = URL(fileURLWithPath: "/repo/b.md")
        let root = URL(fileURLWithPath: "/repo")
        let fixture = makeFixture(files: [fileA, fileB], root: root, defaults: defaults)
        let controllerA = try await openAndAwaitRecording(fixture, file: fileA)
        let controllerB = try await openAndAwaitRecording(fixture, file: fileB)
        try #require(controllerA.window).addTabbedWindow(try #require(controllerB.window), ordered: .above)
        // ヘッドレスのテストプロセスではウィンドウがキーにならず didBecomeKey 通知が飛ばないため、
        // タブ結合後にユーザーがそのタブを操作した状況をデリゲート呼び出しで再現する。
        fixture.manager.viewerWindowDidBecomeKey(controllerB)

        controllerA.close()
        controllerB.close()

        let saved = fixture.store.entries().first { $0.rootPath == root.normalizedPathKey }
        #expect(
            saved?.lastTabGroup?.paths == [fileA.normalizedPathKey, fileB.normalizedPathKey]
        )
    }

    @Test("recordAllRecentRepositoryTabGroups は現在のタブ構成を記録する")
    func recordAllRecordsCurrentTabGroups() async throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let fileB = URL(fileURLWithPath: "/repo/b.md")
        let root = URL(fileURLWithPath: "/repo")
        let fixture = makeFixture(files: [fileA, fileB], root: root, defaults: defaults)
        let controllerA = try await openAndAwaitRecording(fixture, file: fileA)
        let controllerB = try await openAndAwaitRecording(fixture, file: fileB)
        try #require(controllerA.window).addTabbedWindow(try #require(controllerB.window), ordered: .above)

        fixture.manager.recordAllRecentRepositoryTabGroups()

        let saved = fixture.store.entries().first { $0.rootPath == root.normalizedPathKey }
        #expect(
            saved?.lastTabGroup?.paths == [fileA.normalizedPathKey, fileB.normalizedPathKey]
        )
        fixture.manager.allControllers.forEach { $0.close() }
    }

    @Test("recordAllRecentRepositoryTabGroups は保存済みの大きいタブ構成も上書きする")
    func recordAllOverwritesStaleLargerTabGroup() async throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/repo/a.md")
        let root = URL(fileURLWithPath: "/repo")
        let fixture = makeFixture(files: [file], root: root, defaults: defaults)
        _ = try await openAndAwaitRecording(fixture, file: file)
        // ユーザーが以前より少ないタブで終了した状況(保存済みの方が大きい)を作る
        fixture.store.updateLastTabGroup(
            root: root,
            SessionLayout.TabGroup(
                paths: [file.normalizedPathKey, "/repo/gone.md"], selectedPath: file.normalizedPathKey
            )
        )

        fixture.manager.recordAllRecentRepositoryTabGroups()

        let saved = fixture.store.entries().first { $0.rootPath == root.normalizedPathKey }
        #expect(saved?.lastTabGroup?.paths == [file.normalizedPathKey])
        fixture.manager.allControllers.forEach { $0.close() }
    }
}
