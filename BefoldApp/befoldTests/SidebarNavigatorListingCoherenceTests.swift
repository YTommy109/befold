@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 一覧と git 状態が「一緒に」反映されることを検証する(TASK-293)。
///
/// 別々に反映すると、新しいディレクトリの一覧だけが先に届いている間だけ絞り込みが
/// 縮退し(状態が別ディレクトリのものなので絞り込まない)、全件が一瞬描画されてから
/// 絞り込まれる。縮退そのものは TASK-285 の意図した振る舞いなので、縮退を消すのではなく
/// 縮退が起きる空白期間そのものを無くす。
@Suite
@MainActor
struct SidebarNavigatorListingCoherenceTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    @Test("フォルダー移動では、一覧が反映された時点で git 状態も揃っている")
    func appliesListingAndGitStatusTogether() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let changed = dirB.appendingPathComponent("changed.md")
        let clean = dirB.appendingPathComponent("clean.md")
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorListingCoherenceTests"),
            isChangedFilesOnlyAvailable: true
        )
        preference.showChangedFilesOnly = true
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in
                [FileListEntry(url: changed, kind: .file), FileListEntry(url: clean, kind: .file)]
            },
            loadGitStatuses: { directory, _ in
                // git は列挙より遅れて返る。この間に一覧だけを反映してはならない。
                guard directory.normalizedPathKey == dirB.normalizedPathKey else { return .empty }
                for _ in 0 ..< 50 {
                    await Task.yield()
                }
                let status = GitFileStatus(indexChange: nil, worktreeChange: .modified)
                return GitStatusResult(
                    statuses: [changed.normalizedPathKey: status],
                    indexURL: nil,
                    repositoryRoot: base
                )
            }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.navigateToFolder(dirB)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.entries.count == 2)
        #expect(navigator.fileListModel.activeGitChangeFilter != nil)
        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"]
        )
    }
}
