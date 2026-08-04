@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// サイドバーの git 状態取得が、一覧取得とは独立した世代で古い結果を捨てること、
/// およびウィンドウを閉じるときにキャンセルされることを検証する。
/// 実 git もフルウィンドウ生成も伴わない(注入クロージャで差し替える)。
@Suite
@MainActor
struct SidebarNavigatorGitStatusTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// 実ファイルシステム監視を張らずに「どのパスを監視したか」「停止されたか」を記録する。
    final class RecordingWatcher: FileWatching, @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        let path: URL
        /// 監視対象の変更を模して呼ぶ。実 FileWatcher と同じくメインアクターで通知する。
        let fire: @MainActor @Sendable () -> Void

        init(path: URL, fire: @escaping @MainActor @Sendable () -> Void) {
            self.path = path
            self.fire = fire
        }

        var isStopped: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopped
        }

        func stop() {
            lock.lock(); defer { lock.unlock() }
            stopped = true
        }
    }

    private func makeNavigator(
        currentDirectory: URL,
        watchers: LockedBox<[RecordingWatcher]>? = nil,
        loadGitStatuses: @escaping (URL, GitStatusRefreshPolicy) async -> GitStatusResult
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorGitStatusTests")
            ),
            directoryLister: { _, _, _ in [] },
            resolveGitRoot: { _ in nil },
            loadGitStatuses: loadGitStatuses,
            makeGitIndexWatcher: { url, onChange in
                let watcher = RecordingWatcher(path: url, fire: onChange)
                watchers?.update { $0.append(watcher) }
                return watcher
            }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: currentDirectory.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        return (navigator, host)
    }

    private func status(_ change: GitFileStatus.Change) -> GitFileStatus {
        GitFileStatus(indexChange: nil, worktreeChange: change)
    }

    @Test("一覧更新で取得した git 状態が FileListModel に反映される")
    func appliesLoadedStatusesToModel() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-apply")
        let statuses = ["\(base.path)/a.md": status(.modified)]
        let (navigator, host) = makeNavigator(currentDirectory: base) { _, _ in
            GitStatusResult(statuses: statuses, indexURL: nil, repositoryRoot: base)
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        #expect(navigator.fileListModel.gitStatus?.files == statuses)
    }

    /// フォルダー行のバッジは配下の集約なので、状態マップと同じ契機で写像まで済ませる
    /// (行ごとに配下を走査させない)。
    @Test("取得した git 状態からフォルダー配下の集約も FileListModel に反映される")
    func appliesFolderAggregatesToModel() async throws {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-folder")
        let statuses = ["\(base.path)/sub/deep/a.md": status(.modified)]
        let (navigator, host) = makeNavigator(currentDirectory: base) { _, _ in
            GitStatusResult(statuses: statuses, indexURL: nil, repositoryRoot: base)
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        let folder = try #require(navigator.fileListModel.gitStatus?.folderStatus(at: "\(base.path)/sub"))
        #expect(folder.hasUnstaged)
    }

    /// 状態取得は一覧列挙とは別プロセス(git)の所要時間に左右されるため、
    /// 一覧の世代とは独立した世代で古い結果を捨てる必要がある。
    @Test("連続する更新では古い git 状態が新しい結果を上書きしない")
    func discardsStaleStatuses() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-stale")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let staleGate = AsyncGate()
        let freshStatuses = ["\(dirB.path)/b.md": status(.added)]
        let staleStatuses = ["\(base.path)/a.md": status(.deleted)]
        let (navigator, host) = makeNavigator(currentDirectory: base) { directory, _ in
            guard directory.normalizedPathKey != dirB.normalizedPathKey else {
                return GitStatusResult(statuses: freshStatuses, indexURL: nil, repositoryRoot: base)
            }
            await staleGate.wait()
            return GitStatusResult(statuses: staleStatuses, indexURL: nil, repositoryRoot: base)
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        let staleTask = navigator.pendingGitStatusTask
        navigator.navigateToFolder(dirB)
        let freshTask = navigator.pendingGitStatusTask

        // 新しい結果を確定させたあとで、足止めしていた古い結果を返す。
        await freshTask?.value
        staleGate.open()
        await staleTask?.value

        #expect(navigator.fileListModel.gitStatus?.files == freshStatuses)
    }

    // MARK: - Index Watching (TASK-186.2)

    @Test("取得結果の .git/index を監視し、その変更で状態を取り直す")
    func watchesGitIndexAndRefreshesOnChange() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-watch")
        let indexURL = base.appendingPathComponent(".git/index")
        let policies = LockedBox<[GitStatusRefreshPolicy]>([])
        let watchers = LockedBox<[RecordingWatcher]>([])
        let (navigator, host) = makeNavigator(currentDirectory: base, watchers: watchers) { _, policy in
            policies.update { $0.append(policy) }
            return GitStatusResult(statuses: [:], indexURL: indexURL, repositoryRoot: base)
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        #expect(watchers.get().map(\.path) == [indexURL])
        #expect(policies.get() == [.always])

        // index の変更通知が来たら取り直す。ただし `.git` 配下の無関係な書き込みで
        // git を連打しないよう、契機に応じた policy で問い合わせる。
        watchers.get()[0].fire()
        await navigator.pendingGitStatusTask?.value

        #expect(policies.get() == [.always, .onlyIfIndexChanged])
    }

    /// 監視の張り直しは対象パスが変わったときだけ。毎回の refresh で張り直すと
    /// DispatchSource の生成・破棄をディレクトリ移動のたびに繰り返すことになる。
    @Test("同じ .git/index への監視は張り直さない")
    func doesNotRearmWatcherForSameIndexPath() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-rearm")
        let indexURL = base.appendingPathComponent(".git/index")
        let watchers = LockedBox<[RecordingWatcher]>([])
        let (navigator, host) = makeNavigator(currentDirectory: base, watchers: watchers) { _, _ in
            GitStatusResult(statuses: [:], indexURL: indexURL, repositoryRoot: base)
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value
        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        #expect(watchers.get().count == 1)
    }

    @Test("git 管理外へ移動したら index 監視を止める")
    func stopsWatcherWhenLeavingRepository() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-leave")
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let indexURL = base.appendingPathComponent(".git/index")
        let watchers = LockedBox<[RecordingWatcher]>([])
        let (navigator, host) = makeNavigator(currentDirectory: base, watchers: watchers) { directory, _ in
            guard directory.normalizedPathKey == base.normalizedPathKey else { return .empty }
            return GitStatusResult(statuses: [:], indexURL: indexURL, repositoryRoot: base)
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value
        navigator.navigateToFolder(outside)
        await navigator.pendingGitStatusTask?.value

        #expect(watchers.get().count == 1)
        #expect(watchers.get()[0].isStopped)
    }

    @Test("cancelPendingListing で index 監視も止まる")
    func cancelPendingListingStopsWatcher() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-cancelwatch")
        let indexURL = base.appendingPathComponent(".git/index")
        let watchers = LockedBox<[RecordingWatcher]>([])
        let (navigator, host) = makeNavigator(currentDirectory: base, watchers: watchers) { _, _ in
            GitStatusResult(statuses: [:], indexURL: indexURL, repositoryRoot: base)
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value
        navigator.cancelPendingListing()

        #expect(watchers.get()[0].isStopped)
    }

    @Test("cancelPendingListing で git 状態取得タスクも破棄される")
    func cancelPendingListingCancelsStatusTask() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-cancel")
        let gate = AsyncGate()
        let (navigator, host) = makeNavigator(currentDirectory: base) { _, _ in
            await gate.wait()
            return .empty
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        let task = navigator.pendingGitStatusTask
        navigator.cancelPendingListing()

        #expect(navigator.pendingGitStatusTask == nil)
        #expect(task?.isCancelled == true)
        gate.open()
        await task?.value
    }
}
