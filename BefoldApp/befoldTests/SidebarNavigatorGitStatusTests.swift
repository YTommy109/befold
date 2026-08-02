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

    private func makeNavigator(
        currentDirectory: URL,
        loadGitStatuses: @escaping (URL) async -> [String: GitFileStatus]
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: [],
            selection: nil,
            hiddenFilesPreference: HiddenFilesPreference(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorGitStatusTests")
            ),
            directoryLister: { _, _, _ in [] },
            resolveGitRoot: { _ in nil },
            loadGitStatuses: loadGitStatuses
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
        let (navigator, host) = makeNavigator(currentDirectory: base) { _ in statuses }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        #expect(navigator.fileListModel.gitStatuses == statuses)
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
        let (navigator, host) = makeNavigator(currentDirectory: base) { directory in
            guard directory.normalizedPathKey != dirB.normalizedPathKey else { return freshStatuses }
            await staleGate.wait()
            return staleStatuses
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

        #expect(navigator.fileListModel.gitStatuses == freshStatuses)
    }

    @Test("cancelPendingListing で git 状態取得タスクも破棄される")
    func cancelPendingListingCancelsStatusTask() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGitStatusTests-cancel")
        let gate = AsyncGate()
        let (navigator, host) = makeNavigator(currentDirectory: base) { _ in
            await gate.wait()
            return [:]
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
