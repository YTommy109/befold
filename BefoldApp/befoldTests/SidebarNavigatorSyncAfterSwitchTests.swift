@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ファイル切替後のサイドバー同期(`syncAfterSwitch`)が、表示中フォルダーを
/// 動かしてよい場面とそうでない場面を区別できているか(TASK-465)。
///
/// 判定の基準は「いま一覧にその行があるか」であり、レイアウト(tree / drillDown)ではない。
/// tree では展開したサブフォルダーの子行も同じ一覧に並ぶため、親ディレクトリの比較で
/// 判定するとフォルダー移動が誤発火する。
@Suite
@MainActor
struct SidebarNavigatorSyncAfterSwitchTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private func makeNavigator(
        currentDirectory: URL,
        rootEntries: [FileListEntry],
        layoutMode: SidebarLayoutMode,
        childrenLister: @escaping @Sendable (URL, befold.SortOrder, Bool) async -> [FileListEntry]? = { _, _, _ in nil }
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorSyncAfterSwitchTests"),
            isTreeLayoutAvailable: true
        )
        preference.layoutMode = layoutMode
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in DirectoryListing(parentEntry: nil, rootChildren: rootEntries) },
            childrenLister: childrenLister,
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(
            currentFileURL: currentDirectory.appendingPathComponent("fileA.mmd")
        )
        navigator.attach(to: host)
        return (navigator, host)
    }

    /// tree で展開した子ファイルを選んでも、表示中フォルダーと展開状態は動かない(AC #1 / #2)。
    @Test("tree 展開下の子ファイルへ切り替えても currentDirectory と展開が保たれる")
    func treeChildSelectionKeepsCurrentDirectory() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorSyncAfterSwitchTests-tree")
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let child = sub.appendingPathComponent("child.mmd")
        let rootEntries = [
            FileListEntry(url: base.appendingPathComponent("fileA.mmd"), kind: .file),
            FileListEntry(url: sub, kind: .folder),
        ]
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: rootEntries, layoutMode: .tree
        ) { _, _, _ in [FileListEntry(url: child, kind: .file)] }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.expandFolder(sub.normalizedPathKey, at: sub)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(navigator.fileListModel.entries.contains { $0.pathKey == child.normalizedPathKey })

        navigator.syncAfterSwitch(to: child)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == base.normalizedPathKey)
        #expect(navigator.expandedFolderKeys.contains(sub.normalizedPathKey))
        #expect(navigator.fileListModel.selection?.normalizedPathKey == child.normalizedPathKey)
    }

    /// 一覧に無いファイル(Quick Open 等)へ切り替えたら、従来どおりフォルダーが追従する(AC #3)。
    @Test("一覧外のファイルへ切り替えると currentDirectory が追従する")
    func switchToFileOutsideListingFollowsFolder() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorSyncAfterSwitchTests-outside")
        let other = base.appendingPathComponent("other", isDirectory: true)
        let target = other.appendingPathComponent("target.mmd")
        let rootEntries = [FileListEntry(url: base.appendingPathComponent("fileA.mmd"), kind: .file)]
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: rootEntries, layoutMode: .drillDown
        )
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()

        navigator.syncAfterSwitch(to: target)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == other.normalizedPathKey)
    }
}
