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

    /// 絞り込みが OFF のときは一覧を git 状態と揃える理由が無い(縮退しようがない)。
    /// それでも待つと、絞り込みを使っていない利用者までフォルダー移動のたびに
    /// git subprocess の完了を待たされる(TASK-297)。
    @Test("絞り込み OFF のフォルダー移動は git 状態の完了を待たずに一覧を反映する")
    func appliesListingWithoutWaitingForGitWhenFilterIsOff() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests-off")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let changed = dirB.appendingPathComponent("changed.md")
        let clean = dirB.appendingPathComponent("clean.md")
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorListingCoherenceTests-off"),
            isChangedFilesOnlyAvailable: true
        )
        preference.showChangedFilesOnly = false
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in
                [FileListEntry(url: changed, kind: .file), FileListEntry(url: clean, kind: .file)]
            },
            loadGitStatuses: { directory, _ in
                guard directory.normalizedPathKey == dirB.normalizedPathKey else { return .empty }
                for _ in 0 ..< 200 {
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

        // 一覧は git より先に反映される。git 状態はまだ届いていない。
        #expect(navigator.fileListModel.entries.count == 2)
        #expect(navigator.fileListModel.gitStatus == nil)

        // 遅れて届いた git 状態は、そのあときちんと反映される(バッジ用)。
        await navigator.pendingGitStatusTask?.value
        #expect(navigator.fileListModel.gitStatus?.files.isEmpty == false)
    }

    /// `.git/index` の更新とフォルダー移動が同時に起きる状況(TASK-294)。
    /// 移動の待ち合わせ中に単発の refreshGitStatuses が世代を進めても、一覧と対で取った
    /// git 状態は捨ててはならない。捨てると一覧だけが新しいディレクトリのものになり、
    /// 単発の取得が返るまで絞り込みの外れた全件が表示される。
    @Test("移動中に .git/index 由来の取得が割り込んでも一覧と対の git 状態を捨てない")
    func keepsPairedGitStatusWhenSingleRefreshInterleaves() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests-race")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let changed = dirB.appendingPathComponent("changed.md")
        let clean = dirB.appendingPathComponent("clean.md")
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorListingCoherenceTests-race"),
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
            loadGitStatuses: { directory, policy in
                // 割り込む単発の取得。返らないまま結果を待たせ、一覧と対の結果だけで
                // 絞り込みが成立することを見る。
                guard policy == .always else {
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                    return .empty
                }
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
        let listingTask = navigator.pendingListingTask
        // 移動の待ち合わせ中に `.git/index` の発火が届く。
        navigator.refreshGitStatuses(policy: .onlyIfIndexChanged)
        await listingTask?.value

        #expect(navigator.fileListModel.entries.count == 2)
        #expect(navigator.fileListModel.activeGitChangeFilter != nil)
        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"]
        )
    }
}
