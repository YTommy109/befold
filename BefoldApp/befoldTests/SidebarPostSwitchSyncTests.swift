@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ファイル切替後と履歴適用後の同期区間が `SidebarPostSwitchSync` の 1 本に畳まれている
/// ことを、**両方の入口から同じ不変条件で** 押さえる(TASK-471)。
///
/// 押さえる不変条件は 2 つ。
/// - **選択は同期区間で確定する(TASK-445)。** 一覧の着地を待たずに確定していること。
///   各テストは `awaitSettled()` を挟まずに検証する(挟むと着地側の上積みが救ってしまい、
///   区間で確定しなくなっても落ちない)。
/// - **表示中フォルダーの移動は `moveCurrentDirectory` を通る(TASK-465)。** 直接代入だと
///   展開の破棄が素通りするため、移動後に展開が残っていないことで検出する。
///
/// 片方の入口だけを直しても兄弟に穴が残る形だったので、同型のテストを 2 つ並べている。
/// 畳んだ実装を片側へ書き戻すと、書き戻さなかった側がここで落ちる。
@Suite
@MainActor
struct SidebarPostSwitchSyncTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private struct Fixture {
        let base: URL
        let sub: URL
        let child: URL
        let sibling: URL
        let outside: URL
        let outsideFile: URL
        let inner: URL
        let deepChild: URL
    }

    private func makeFixture(_ name: String) -> Fixture {
        let base = Self.home.appendingPathComponent("SidebarPostSwitchSyncTests-\(name)")
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let inner = sub.appendingPathComponent("inner", isDirectory: true)
        return Fixture(
            base: base,
            sub: sub,
            child: sub.appendingPathComponent("child.mmd"),
            sibling: base.appendingPathComponent("a.mmd"),
            outside: outside,
            outsideFile: outside.appendingPathComponent("target.mmd"),
            inner: inner,
            deepChild: inner.appendingPathComponent("deep.mmd")
        )
    }

    /// ディレクトリごとの固定エントリを返す lister と、展開用の子 lister を備えた
    /// ナビゲーターを作る(前例: SidebarNavigatorHistoryTests)。実 FS には触れない。
    private func makeNavigator(
        _ fixture: Fixture,
        currentDirectory: URL,
        selection: URL?,
        currentFile: URL
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let listings: [String: [FileListEntry]] = [
            fixture.base.normalizedPathKey: [
                FileListEntry(url: fixture.sub, kind: .folder),
                FileListEntry(url: fixture.sibling, kind: .file),
            ],
            fixture.sub.normalizedPathKey: [
                FileListEntry(url: fixture.inner, kind: .folder),
                FileListEntry(url: fixture.child, kind: .file),
            ],
            fixture.inner.normalizedPathKey: [FileListEntry(url: fixture.deepChild, kind: .file)],
            fixture.outside.normalizedPathKey: [FileListEntry(url: fixture.outsideFile, kind: .file)],
        ]
        let listing = { (url: URL) -> DirectoryListing in
            DirectoryListing(rootChildren: listings[url.normalizedPathKey] ?? [])
        }
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "SidebarPostSwitchSyncTests")
        )
        preference.record { $0.layoutMode = .tree }
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: listing(currentDirectory).rows(),
            selection: selection,
            displayDefaults: preference,
            directoryLister: { url, _, _ in listing(url) },
            childrenLister: { url, _, _ in listings[url.normalizedPathKey] },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: currentFile)
        navigator.attach(to: host)
        return (navigator, host)
    }

    /// `sub` を展開した状態にする。展開が実際に行へ載ったことまで確かめる。
    private func expandSub(_ navigator: SidebarNavigator, _ fixture: Fixture) async {
        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.expandFolder(fixture.sub.normalizedPathKey, at: fixture.sub)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(navigator.expandedFolderKeys.contains(fixture.sub.normalizedPathKey))
    }

    /// `sub` の中の `inner` も展開した状態にする(2 階層ぶん)。
    private func expandSubAndInner(_ navigator: SidebarNavigator, _ fixture: Fixture) async {
        await expandSub(navigator, fixture)
        navigator.expandFolder(fixture.inner.normalizedPathKey, at: fixture.inner)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(navigator.expandedFolderKeys.contains(fixture.inner.normalizedPathKey))
    }

    @Test("ファイル切替: 2 階層展開済みの子ファイルを開いてもフォルダー移動は起きない")
    func fileSwitchStaysWhenTwoLevelsDeepChildIsAlreadyExpanded() async {
        let fixture = makeFixture("switch-two-levels")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: fixture.sibling, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        await expandSubAndInner(navigator, fixture)

        host.performFileSwitch(to: fixture.deepChild)
        navigator.syncAfterSwitch(to: fixture.deepChild)

        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == fixture.base.normalizedPathKey)
        #expect(navigator.expandedFolderKeys.contains(fixture.sub.normalizedPathKey))
        #expect(navigator.expandedFolderKeys.contains(fixture.inner.normalizedPathKey))
    }

    @Test("ファイル切替: 選択は一覧の着地を待たずに同期区間で確定する")
    func fileSwitchConfirmsSelectionWithoutWaitingForListing() async {
        let fixture = makeFixture("switch-selection")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: fixture.sibling, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        navigator.refreshFileList()
        await navigator.awaitSettled()

        host.performFileSwitch(to: fixture.outsideFile)
        navigator.syncAfterSwitch(to: fixture.outsideFile)

        // ここで await しない。着地前に確定していなければ選択は旧のまま(a.mmd)になる。
        #expect(navigator.fileListModel.selection?.normalizedPathKey == fixture.outsideFile.normalizedPathKey)
        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == fixture.outside.normalizedPathKey)
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.selection?.normalizedPathKey == fixture.outsideFile.normalizedPathKey)
    }

    @Test("ファイル切替: フォルダーの移動は moveCurrentDirectory を通り展開が捨てられる")
    func fileSwitchMovePassesThroughMoveCurrentDirectory() async {
        let fixture = makeFixture("switch-move")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.base,
            selection: fixture.sibling, currentFile: fixture.sibling
        )
        defer { withExtendedLifetime(host) {} }
        await expandSub(navigator, fixture)

        host.performFileSwitch(to: fixture.outsideFile)
        navigator.syncAfterSwitch(to: fixture.outsideFile)

        #expect(navigator.expandedFolderKeys.isEmpty)
    }

    @Test("履歴適用: 選択は一覧の着地を待たずに同期区間で確定する")
    func historyApplyConfirmsSelectionWithoutWaitingForListing() async {
        let fixture = makeFixture("history-selection")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.sub,
            selection: fixture.child, currentFile: fixture.child
        )
        defer { withExtendedLifetime(host) {} }
        // sub で child.mmd を提示している状態を積み、親へ上がってから戻る。
        navigator.recordHistory()
        navigator.navigateToFolder(fixture.base)
        await navigator.awaitSettled()

        navigator.navigateHistory(by: -1)

        // ここでも await しない(上のテストと同じ理由)。
        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == fixture.sub.normalizedPathKey)
        #expect(navigator.fileListModel.selection?.normalizedPathKey == fixture.child.normalizedPathKey)
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.selection?.normalizedPathKey == fixture.child.normalizedPathKey)
    }

    @Test("履歴適用: フォルダーの移動は moveCurrentDirectory を通り展開が捨てられる")
    func historyApplyMovePassesThroughMoveCurrentDirectory() async {
        let fixture = makeFixture("history-move")
        let (navigator, host) = makeNavigator(
            fixture, currentDirectory: fixture.sub,
            selection: fixture.child, currentFile: fixture.child
        )
        defer { withExtendedLifetime(host) {} }
        navigator.recordHistory()
        navigator.navigateToFolder(fixture.base)
        await navigator.awaitSettled()
        await expandSub(navigator, fixture)

        navigator.navigateHistory(by: -1)

        #expect(navigator.fileListModel.currentDirectory.normalizedPathKey == fixture.sub.normalizedPathKey)
        #expect(navigator.expandedFolderKeys.isEmpty)
    }
}
