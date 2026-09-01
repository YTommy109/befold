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
///
/// 反映待ちには**壁時計予算を持たない**待機（`waitForDeliveryOnMainActor` /
/// `waitForMainActorDelivery`）を使う。記録は `RecentRepositoryRecorder.recordIfNeeded` が
/// MainActor 上で起こす `Task` から始まるため、待っているのは「解決にかかる時間」ではなく
/// **メインアクターの順番待ち**である。全体実行では多数の `@MainActor` スイートが
/// メインアクターを直列に占有するので、予算付きの待機は操作の成否と無関係に切れる
/// (TASK-527 の実測: 4 回中 2 回、8 件すべてが `waitUntil が 10.0 seconds 以内に
/// 条件を満たさなかった` で落ちた。単体実行では 1.4 秒で通る)。
/// 戻らない回帰の打ち切りはスイートの `.timeLimit` が担う。
@Suite(testTimeLimit())
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

    /// 特定ファイルの root 解決だけを合図まで止められるフェイク。
    /// 「解決が着地する前に別リポジトリのファイルへ切り替わる」順序を再現するために使う。
    private final class GatedGitFileIndex: GitFileIndexing, @unchecked Sendable {
        /// パス接頭辞 -> リポジトリルートの対応。
        private let roots: [String: URL]
        /// この URL の解決だけ gate が開くまで待つ。
        private let gatedPath: String
        private let gate = DispatchSemaphore(value: 0)
        /// gate を通過して解決を再開したかどうか(テスト側が着地待ちの起点にする)。
        let didResumeGatedLookup = LockedBox(false)

        init(roots: [String: URL], gatedPath: String) {
            self.roots = roots
            self.gatedPath = gatedPath
        }

        func openGate() {
            gate.signal()
        }

        func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
            nil
        }

        func repositoryRoot(forFileAt url: URL) -> URL? {
            if url.normalizedPathKey == gatedPath {
                waitOrRecordTimeout(gate, "GatedGitFileIndex.repositoryRoot")
                didResumeGatedLookup.set(true)
            }
            return roots.first { url.path.hasPrefix($0.key) }?.value
        }

        func warm(forFileAt _: URL) {}
    }

    private struct Fixture {
        let manager: ViewerWindowManager
        let store: RecentRepositoriesStore
    }

    /// - Parameter resolveIdentity: 既定は「本体リポジトリそのもの」(mainRoot == root)。
    ///   worktree の記録規約を見るテストだけが、別の本体ルートを返す解決へ差し替える。
    /// - Parameter gitFileIndex: 既定は root を固定で返すフェイク。解決の順序を操るテストだけが
    ///   独自の索引を渡す。
    private func makeFixture(
        files: [URL], root: URL?, defaults: UserDefaults,
        gitFileIndex: (any GitFileIndexing)? = nil,
        resolveIdentity: @escaping @Sendable (URL) -> RepositoryIdentity = {
            RepositoryIdentity(label: $0.lastPathComponent, mainRoot: $0)
        }
    ) -> Fixture {
        let fileReader = InMemoryFileReader(
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.path, "graph TD;") })
        )
        let sessionStore = SessionStore(defaults: defaults)
        let recentDocumentsStore = RecentDocumentsStore(defaults: defaults)
        let recentRepositoriesStore = RecentRepositoriesStore(defaults: defaults)
        let gitFileIndex = gitFileIndex ?? FixedRootGitFileIndex(root: root)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            displayDefaults: SidebarDisplayDefaults(defaults: defaults),
            diffDisplayPreference: DiffDisplayPreference(defaults: defaults),
            findOptionsPreference: FindOptionsPreference(defaults: defaults),
            headingJumpLevelDefaults: HeadingJumpLevelDefaults(defaults: defaults),
            codeFontPreference: CodeFontPreference(defaults: defaults),
            csvNumberFormatPreference: CsvNumberFormatPreference(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults),
            windowFrame: WindowFrameStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            fileReader: fileReader,
            makeStore: { _ in
                ViewerStore(
                    watcherFactory: { _, _, _, _ in MockFileWatcher() },
                    fileReader: fileReader,
                    defaults: defaults
                )
            },
            makeContentView: placeholderViewerContent,
            gitFileIndex: gitFileIndex,
            recentRepositoriesStore: recentRepositoriesStore,
            repositoryIdentityResolver: resolveIdentity
        )
        return Fixture(manager: manager, store: recentRepositoriesStore)
    }

    /// 指定ファイルのウィンドウを開き、非同期の git 解決が反映されるまで待って返す。
    private func openAndAwaitRecording(
        _ fixture: Fixture, file: URL, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> ViewerWindowController {
        fixture.manager.openViewer(for: file)
        let controller = try #require(
            fixture.manager.controllers[file.normalizedPathKey]?.first, sourceLocation: sourceLocation
        )
        await waitForDeliveryOnMainActor { controller.repositoryRoot != nil }
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

    /// RecentRepositoryEntry の規約: mainRoot を持たせるのは worktree のときだけで、
    /// 本体リポジトリそのものなら nil。両方向を見ないと「常に埋める」実装でも通ってしまう。
    @Test("worktree を開いたときだけ本体ルートが記録される")
    func recordsMainRootOnlyForWorktree() async throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentReposWorktree")
        let file = URL(fileURLWithPath: "/wt/a.md")
        let root = URL(fileURLWithPath: "/wt")
        let mainRoot = URL(fileURLWithPath: "/main-repo")
        let fixture = makeFixture(
            files: [file], root: root, defaults: defaults,
            resolveIdentity: { _ in RepositoryIdentity(label: "wt", mainRoot: mainRoot) }
        )

        _ = try await openAndAwaitRecording(fixture, file: file)

        #expect(fixture.store.entries().map(\.mainRootPath) == [mainRoot.normalizedPathKey])
        fixture.manager.allControllers.forEach { $0.close() }
    }

    @Test("git 管理外のファイルを開いても記録されない")
    func openingFileOutsideRepositoryDoesNotRecordAnything() async {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/standalone/a.md")
        let index = FixedRootGitFileIndex(root: nil)
        let fixture = makeFixture(files: [file], root: nil, defaults: defaults, gitFileIndex: index)

        fixture.manager.openViewer(for: file)

        // root が nil と分かった時点で記録経路は打ち切られる。解決が済んだことを
        // 待ってから判定することで、「まだ走っていないだけ」の空を成功と誤認しない。
        await waitForMainActorDelivery { index.rootLookupCount.get() > 0 }
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
        fixture.manager.sessionSync.viewerWindowDidBecomeKey(controllerB)

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

    /// TASK-461: 解決は detached タスクで着地するため、着地時の対象が解決を開始した対象と
    /// 同じであることを確認しないと、切替前のリポジトリが現在のリポジトリとして書き込まれる。
    @Test("解決の着地前に別リポジトリへ切り替わったら記録もルートの書き込みも行わない")
    func switchingFileBeforeResolutionLandsRecordsNothing() async throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentReposSwitch")
        let fileA = URL(fileURLWithPath: "/repoA/a.md")
        let fileB = URL(fileURLWithPath: "/repoB/b.md")
        let rootA = URL(fileURLWithPath: "/repoA")
        let rootB = URL(fileURLWithPath: "/repoB")
        // gate を通過した解決が着地し切ったことを見るための、堰き止めない対照。
        let fileC = URL(fileURLWithPath: "/repoB/c.md")
        let index = GatedGitFileIndex(
            roots: ["/repoA": rootA, "/repoB": rootB], gatedPath: fileA.normalizedPathKey
        )
        let fixture = makeFixture(
            files: [fileA, fileB, fileC], root: nil, defaults: defaults, gitFileIndex: index
        )

        fixture.manager.openViewer(for: fileA)
        let controller = try #require(fixture.manager.controllers[fileA.normalizedPathKey]?.first)
        // 解決が止まっている間に別リポジトリのファイルへ切り替える。
        controller.performFileSwitch(to: fileB)
        try #require(controller.fileURL.normalizedPathKey == fileB.normalizedPathKey)
        index.openGate()

        await waitForMainActorDelivery { index.didResumeGatedLookup.get() }
        // 着地(MainActor への戻り)が済んでから判定する。固定 sleep では全体実行の
        // 混雑時に「まだ着地していないだけ」の空を成功と誤認するため、gate 通過後に
        // 別ウィンドウの記録を最後まで通し、それが着地したことをバリアにする。
        let controllerC = try await openAndAwaitRecording(fixture, file: fileC)

        #expect(controllerC.repositoryRoot == rootB)
        #expect(controller.repositoryRoot == nil)
        #expect(fixture.store.entries().map(\.rootPath) == [rootB.normalizedPathKey])
        fixture.manager.allControllers.forEach { $0.close() }
    }
}
