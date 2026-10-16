import AppKit
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
    /// scrollRowToVisible の要求行を記録するスパイ(FileListModelScrollTests と同型)。
    private final class SpyTableView: NSTableView {
        private(set) var scrolledRows: [Int] = []
        override func scrollRowToVisible(_ row: Int) {
            scrolledRows.append(row)
        }
    }

    private static let home = FileManager.default.temporaryDirectory

    private func makeNavigator(
        currentDirectory: URL,
        rootEntries: [FileListEntry],
        layoutMode: SidebarLayoutMode,
        childrenLister: @escaping @Sendable (URL, befold.SortOrder, Bool) async -> [FileListEntry]? = { _, _, _ in nil }
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorSyncAfterSwitchTests")
        )
        preference.record { $0.layoutMode = layoutMode }
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: [],
            selection: nil,
            home: FileManager.default.temporaryDirectory,
            displayDefaults: preference,
            directoryLister: { _, _, _ in DirectoryListing(rootChildren: rootEntries) },
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
        await navigator.awaitSettled()
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

    /// tree でルート配下の畳まれたフォルダー内のファイルへ切り替えると、移動せず祖先を開いて選ぶ(TASK-708)。
    @Test("tree で畳まれた深い階層のファイルへ切り替えてもルートは動かず祖先が展開される")
    func treeCollapsedDescendantRevealsWithoutMoving() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorSyncAfterSwitchTests-reveal")
        let other = base.appendingPathComponent("other", isDirectory: true)
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let deep = sub.appendingPathComponent("deep", isDirectory: true)
        let target = deep.appendingPathComponent("target.mmd")
        let rootEntries = [
            FileListEntry(url: other, kind: .folder),
            FileListEntry(url: sub, kind: .folder),
        ]
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: rootEntries, layoutMode: .tree
        ) { dir, _, _ in
            switch dir.normalizedPathKey {
            case sub.normalizedPathKey: [FileListEntry(url: deep, kind: .folder)]
            case deep.normalizedPathKey: [FileListEntry(url: target, kind: .file)]
            default: []
            }
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.expandFolder(other.normalizedPathKey, at: other)
        await navigator.awaitSettled()

        navigator.syncAfterSwitch(to: target)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == base.normalizedPathKey)
        #expect(navigator.expandedFolderKeys.isSuperset(of: [
            other.normalizedPathKey, sub.normalizedPathKey, deep.normalizedPathKey,
        ]))
        #expect(navigator.fileListModel.selection?.normalizedPathKey == target.normalizedPathKey)
    }

    /// tree でもルート外のファイルは従来どおり親フォルダーへ移る(TASK-708)。
    @Test("tree でルート外のファイルへ切り替えると親フォルダーへ移動する")
    func treeOutsideRootStillMoves() async {
        let prefix = "SidebarNavigatorSyncAfterSwitchTests-treeout"
        let base = Self.home.appendingPathComponent(prefix)
        let sibling = Self.home.appendingPathComponent("\(prefix)2", isDirectory: true)
        let target = sibling.appendingPathComponent("target.mmd")
        let (navigator, host) = makeNavigator(currentDirectory: base, rootEntries: [], layoutMode: .tree)
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.syncAfterSwitch(to: target)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == sibling.normalizedPathKey)
    }

    /// 隠しフォルダー配下(showHiddenFiles OFF で行が出ない)は、選択だけが付いてフォルダー一覧へ落ちないよう従来どおり移動する(TASK-708 AC #7)。
    @Test("tree で隠しフォルダー配下のファイルへ切り替えると親フォルダーへ移動する")
    func treeHiddenAncestorMoves() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorSyncAfterSwitchTests-hidden")
        let hidden = base.appendingPathComponent(".hidden", isDirectory: true)
        let target = hidden.appendingPathComponent("target.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: base,
            rootEntries: [FileListEntry(url: base.appendingPathComponent("a.mmd"), kind: .file)],
            layoutMode: .tree
        ) { _, _, _ in [FileListEntry(url: target, kind: .file)] }
        defer { withExtendedLifetime(host) {} }
        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.syncAfterSwitch(to: target)
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == hidden.normalizedPathKey)
    }

    /// 子リストの着地が遅れても、選択行が着地した時点でその行へのスクロールが要求される(TASK-708 AC #3)。
    @Test("tree で祖先の子リストが遅れて着地しても、選択行へスクロールを要求する")
    func treeRevealScrollsEvenWhenChildrenLandLate() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorSyncAfterSwitchTests-late")
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let target = sub.appendingPathComponent("target.mmd")
        let rootEntries = [
            FileListEntry(url: base.appendingPathComponent("a.mmd"), kind: .file),
            FileListEntry(url: sub, kind: .folder),
        ]
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: rootEntries, layoutMode: .tree
        ) { _, _, _ in
            try? await Task.sleep(for: .milliseconds(200))
            return [FileListEntry(url: target, kind: .file)]
        }
        defer { withExtendedLifetime(host) {} }
        navigator.refreshFileList()
        await navigator.awaitSettled()
        let spy = SpyTableView()
        navigator.fileListModel.tableFocuser.tableView = spy

        navigator.syncAfterSwitch(to: target)
        // 子リストはまだ着地していない: 行が無いのでスクロールは要求できない。
        await drainMainQueue()
        #expect(!navigator.fileListModel.entries.contains { $0.url == target })
        #expect(spy.scrolledRows.isEmpty)

        await navigator.awaitSettled()
        await drainMainQueue()
        let row = navigator.fileListModel.entries.firstIndex { $0.url == target }
        #expect(row != nil)
        #expect(spy.scrolledRows.last == row)
    }
}
