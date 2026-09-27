@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// レビュー表示(ツリー × 変更のみ)で変更ファイルの祖先フォルダーを自動展開する規則(TASK-637)。
///
/// 展開集合は `expandFolder` の時点で書かれる(子リストの着地を待たない)ので、
/// 検証は `expandedFolderKeys` を直接見る。
@Suite
@MainActor
struct SidebarNavigatorReviewExpansionTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private nonisolated static let modified = GitFileStatus(indexChange: nil, worktreeChange: .modified)

    /// テストごとの窓と、差し替え可能な git 状態。
    private struct Fixture {
        let navigator: SidebarNavigator
        let host: SidebarNavigatorStubHost
        let base: URL
        let statuses: LockedBox<[String: GitFileStatus]>

        func key(_ relative: String) -> String {
            base.appendingPathComponent(relative).normalizedPathKey
        }
    }

    private func makeFixture(
        _ name: String,
        layoutMode: SidebarLayoutMode,
        changedFilesOnly: Bool,
        changedFiles: [String]
    ) -> Fixture {
        let prefix = "SidebarNavigatorReviewExpansionTests-\(name)"
        let base = Self.home.appendingPathComponent(prefix)
        let preference = SidebarDisplayDefaults(defaults: makeIsolatedDefaults(prefix: prefix))
        preference.record {
            $0.layoutMode = layoutMode
            $0.showChangedFilesOnly = changedFilesOnly
        }
        let statuses = LockedBox(Dictionary(uniqueKeysWithValues: changedFiles.map {
            (base.appendingPathComponent($0).normalizedPathKey, Self.modified)
        }))
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            displayDefaults: preference,
            directoryLister: { directory, _, _ in
                DirectoryListing(rootChildren: [
                    FileListEntry(url: directory.appendingPathComponent("a"), kind: .folder),
                    FileListEntry(url: directory.appendingPathComponent("b"), kind: .folder),
                ])
            },
            childrenLister: { _, _, _ in [] },
            git: SidebarGitReadingStub(
                repositoryRoot: { _ in base },
                statuses: { _, _ in
                    GitStatusResult(
                        snapshot: GitStatusSnapshot(statuses: statuses.get(), indexURL: nil),
                        repositoryRoot: base
                    )
                }
            ),
            makeGitIndexWatcher: { url, onChange in RecordingWatcher(path: url, fire: onChange) }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        return Fixture(navigator: navigator, host: host, base: base, statuses: statuses)
    }

    private func settle(_ navigator: SidebarNavigator) async {
        await navigator.awaitSettled()
        await navigator.awaitSettled()
    }

    @Test(
        "変更のみ→ツリー／ツリー→変更のみのどちらの順で入っても、同じ祖先フォルダーが展開される",
        arguments: [SidebarDisplayChange.toggleLayoutMode, .toggleChangedFilesOnly]
    )
    func bothOrdersRevealSameFolders(lastToggle: SidebarDisplayChange) async {
        let entersByTree = lastToggle == .toggleLayoutMode
        let fixture = makeFixture(
            entersByTree ? "order-tree-last" : "order-changed-last",
            layoutMode: entersByTree ? .drillDown : .tree,
            changedFilesOnly: entersByTree,
            changedFiles: ["a/deep/x.md", "b/y.md"]
        )
        defer { withExtendedLifetime(fixture.host) {} }
        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)
        #expect(fixture.navigator.expandedFolderKeys.isEmpty)

        fixture.navigator.applyDisplayChange(lastToggle)
        await settle(fixture.navigator)

        #expect(fixture.navigator.expandedFolderKeys
            == [fixture.key("a"), fixture.key("a/deep"), fixture.key("b")])
    }

    @Test("入る前から開いていたフォルダーは閉じられない（和集合）")
    func keepsExistingExpansion() async {
        let fixture = makeFixture(
            "union", layoutMode: .tree, changedFilesOnly: false, changedFiles: ["a/x.md"]
        )
        defer { withExtendedLifetime(fixture.host) {} }
        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)
        fixture.navigator.expandFolder(fixture.key("b"), at: fixture.base.appendingPathComponent("b"))

        fixture.navigator.applyDisplayChange(.toggleChangedFilesOnly)
        await settle(fixture.navigator)

        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("a"), fixture.key("b")])
    }

    @Test("閉じたフォルダーは git 更新で開き直らず、新しく変更を持つフォルダーだけが開く")
    func gitUpdateRevealsOnlyNewlyChangedFolders() async {
        let fixture = makeFixture(
            "git-update", layoutMode: .tree, changedFilesOnly: true, changedFiles: ["a/x.md"]
        )
        defer { withExtendedLifetime(fixture.host) {} }
        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)
        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("a")])
        fixture.navigator.collapseFolder(fixture.key("a"))

        fixture.statuses.update { $0[fixture.key("b/y.md")] = Self.modified }
        fixture.navigator.refreshGitStatuses()
        await settle(fixture.navigator)
        // フォーカス復帰と同じ取り直しでも開き直らない。
        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)

        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("b")])
    }

    @Test("レビュー表示中に別のフォルダーへ移動すると、移動先で同じ規則が適用される")
    func movingReappliesRule() async {
        let fixture = makeFixture(
            "move", layoutMode: .tree, changedFilesOnly: true, changedFiles: ["a/x.md", "b/c/y.md"]
        )
        defer { withExtendedLifetime(fixture.host) {} }
        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)

        fixture.navigator.navigateToFolder(fixture.base.appendingPathComponent("b"))
        await settle(fixture.navigator)

        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("b/c")])
    }

    @Test("解除しても展開は残り、ツリーへ戻すと残った展開に和集合で再適用される")
    func leavingKeepsExpansionAndReenteringUnions() async {
        let fixture = makeFixture(
            "leave", layoutMode: .tree, changedFilesOnly: true, changedFiles: ["a/x.md"]
        )
        defer { withExtendedLifetime(fixture.host) {} }
        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)

        fixture.navigator.applyDisplayChange(.toggleChangedFilesOnly)
        await settle(fixture.navigator)
        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("a")])

        fixture.navigator.collapseFolder(fixture.key("a"))
        fixture.navigator.expandFolder(fixture.key("b"), at: fixture.base.appendingPathComponent("b"))
        fixture.navigator.applyDisplayChange(.toggleChangedFilesOnly)
        await settle(fixture.navigator)

        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("a"), fixture.key("b")])
    }

    @Test("ツリーを外しても展開は残り、ツリーへ戻すと閉じていた変更フォルダーが再び開く")
    func leavingTreeKeepsExpansionAndReenteringReapplies() async {
        let fixture = makeFixture(
            "leave-tree", layoutMode: .tree, changedFilesOnly: true, changedFiles: ["a/x.md"]
        )
        defer { withExtendedLifetime(fixture.host) {} }
        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)
        fixture.navigator.collapseFolder(fixture.key("a"))
        fixture.navigator.expandFolder(fixture.key("b"), at: fixture.base.appendingPathComponent("b"))

        fixture.navigator.applyDisplayChange(.toggleLayoutMode)
        await settle(fixture.navigator)
        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("b")])

        fixture.navigator.applyDisplayChange(.toggleLayoutMode)
        await settle(fixture.navigator)

        #expect(fixture.navigator.expandedFolderKeys == [fixture.key("a"), fixture.key("b")])
    }
}
