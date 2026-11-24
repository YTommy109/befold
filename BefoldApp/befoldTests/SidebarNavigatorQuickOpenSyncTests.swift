@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// Quick Open で別フォルダーのファイルを開いたときに、フォルダー移動だけが反映されて
/// 本文が切り替わらない事象(TASK-445)の回帰テスト。
///
/// 症状の本体は「`previewTarget` が `.folder` のまま残る」こと。ViewerContentView は
/// `previewTarget.folderURL != nil` のあいだフォルダー一覧を本文に重ね、ViewerWebView を
/// opacity 0 で隠すため、旧内容が残って見える。
///
/// 一覧の取得はここでは**決して着地させない**(AsyncGate を開けない)。着地に依存せず
/// 提示対象が決まることがこのスイートの検証点で、着地させてしまうと後追いの選択確定に
/// 隠れて回帰が見えなくなる。
@Suite
@MainActor
struct SidebarNavigatorQuickOpenSyncTests {
    private static let home = FileManager.default.temporaryDirectory

    private struct Fixture {
        let navigator: SidebarNavigator
        let host: SidebarNavigatorStubHost
        let base: URL
        let sub: URL
        let target: URL
    }

    /// base に「fileA.mmd」と「sub/」を出し、別フォルダー other の列挙は永久に足止めする。
    private func makeFixture(gate: AsyncGate) -> Fixture {
        let base = Self.home.appendingPathComponent("SidebarNavigatorQuickOpenSyncTests-base")
        let other = Self.home.appendingPathComponent("SidebarNavigatorQuickOpenSyncTests-other")
        let fileA = base.appendingPathComponent("fileA.mmd")
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let target = other.appendingPathComponent("target.mmd")
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            home: FileManager.default.temporaryDirectory,
            displayDefaults: SidebarDisplayDefaults(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorQuickOpenSyncTests")
            ),
            directoryLister: { url, _, _ in
                guard url.normalizedPathKey == base.normalizedPathKey else {
                    await gate.wait()
                    return DirectoryListing(rootChildren: [FileListEntry(url: target, kind: .file)]
                    )
                }
                return DirectoryListing(rootChildren: [
                    FileListEntry(url: fileA, kind: .file), FileListEntry(url: sub, kind: .folder),
                ])
            },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: fileA)
        navigator.attach(to: host)
        return Fixture(navigator: navigator, host: host, base: base, sub: sub, target: target)
    }

    /// フォルダー行を選んでいる(= 一覧を出している)状態から Quick Open で別フォルダーの
    /// ファイルを開いたとき。選択の確定を一覧の着地に委ねていると、旧フォルダーの選択が
    /// 残って `.folder` のままになる(AC #1 / #2)。
    @Test("フォルダー選択中に別フォルダーのファイルへ切り替えても、フォルダー提示のまま残らない")
    func switchFromFolderSelectionLeavesFolderPresentation() async {
        let gate = AsyncGate()
        let fixture = makeFixture(gate: gate)
        let navigator = fixture.navigator
        defer { withExtendedLifetime(fixture.host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.fileListModel.selection = fixture.sub
        #expect(navigator.fileListModel.previewTarget.folderURL == fixture.sub)

        _ = fixture.host.performFileSwitch(to: fixture.target)
        navigator.syncAfterSwitch(to: fixture.target)

        // 一覧はまだ届いていない。それでも本文側が提示されていなければならない。
        #expect(navigator.fileListModel.previewTarget.folderURL == nil)
        #expect(navigator.fileListModel.selection?.normalizedPathKey == fixture.target.normalizedPathKey)
    }

    /// 選択が無い(navigateToFolder 直後など)状態からでも同じであること(AC #1)。
    @Test("選択が無い状態から別フォルダーのファイルへ切り替えても、フォルダー提示のまま残らない")
    func switchFromNoSelectionLeavesFolderPresentation() async {
        let gate = AsyncGate()
        let fixture = makeFixture(gate: gate)
        let navigator = fixture.navigator
        defer { withExtendedLifetime(fixture.host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.fileListModel.selection = nil
        #expect(navigator.fileListModel.previewTarget.folderURL != nil)

        _ = fixture.host.performFileSwitch(to: fixture.target)
        navigator.syncAfterSwitch(to: fixture.target)

        #expect(navigator.fileListModel.previewTarget.folderURL == nil)
    }

    /// 同一フォルダー内の切替でも扱いは同じ(AC #3: 分岐で非対称にしない)。
    @Test("同一フォルダー内の切替でも選択は同期的に確定する")
    func switchWithinSameFolderConfirmsSelectionSynchronously() async {
        let gate = AsyncGate()
        let fixture = makeFixture(gate: gate)
        let navigator = fixture.navigator
        let sibling = fixture.base.appendingPathComponent("fileA.mmd")
        defer { withExtendedLifetime(fixture.host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.fileListModel.selection = fixture.sub

        _ = fixture.host.performFileSwitch(to: sibling)
        navigator.syncAfterSwitch(to: sibling)

        #expect(navigator.fileListModel.previewTarget == .file)
        #expect(navigator.fileListModel.selection?.normalizedPathKey == sibling.normalizedPathKey)
    }

    /// ツリー表示で、ルート配下の畳まれたサブフォルダー内のファイルへ切り替えたとき(#794)。
    /// 子リストの取得はゲートで止め、展開が着地するまでの間を観測する。その間に一度でも
    /// `.folder` を通ると、本文にルートの一覧が一瞬重なる。
    @Test("ツリーで畳まれたサブフォルダー内のファイルへ切り替えても、展開待ちの間にフォルダー提示を通らない")
    func treeRevealIntoCollapsedFolderNeverPresentsFolder() async throws {
        let gate = AsyncGate()
        let base = Self.home.appendingPathComponent("SidebarNavigatorQuickOpenSyncTests-tree")
        let fileA = base.appendingPathComponent("fileA.mmd")
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let deep = sub.appendingPathComponent("deep.mmd")
        let defaults = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorQuickOpenSyncTests-tree")
        )
        defaults.record(SidebarDisplaySettings(
            showHiddenFiles: false, showChangedFilesOnly: false, layoutMode: .tree, sortOrder: .foldersFirst
        ))
        let navigator = SidebarNavigator(
            currentDirectory: base, entries: [], selection: fileA,
            home: FileManager.default.temporaryDirectory, displayDefaults: defaults,
            directoryLister: { _, _, _ in
                DirectoryListing(rootChildren: [
                    FileListEntry(url: sub, kind: .folder), FileListEntry(url: fileA, kind: .file),
                ])
            },
            childrenLister: { _, _, _ in
                await gate.wait()
                return [FileListEntry(url: deep, kind: .file)]
            },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: fileA)
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        navigator.refreshFileList()
        await navigator.awaitSettled()
        let model = navigator.fileListModel
        try #require(model.previewTarget == .file)

        var targets: [PreviewTarget] = []
        model.onPresentationTargetChange = { targets.append(model.previewTarget) }
        _ = host.performFileSwitch(to: deep)
        navigator.syncAfterSwitch(to: deep)

        // 展開はまだ着地していない。本文側を出したままで、履歴にもファイル提示として残る。
        #expect(model.previewTarget.folderURL == nil)
        let recorded = navigator.navigationHistory.entries.last?.presentation
        guard case let .file(url) = recorded else {
            Issue.record("履歴がファイル提示ではない: \(String(describing: recorded))")
            return
        }
        #expect(url.normalizedPathKey == deep.normalizedPathKey)

        gate.open()
        await navigator.awaitSettled()
        #expect(model.previewTarget == .file)
        #expect(!targets.contains { $0.folderURL != nil }, "途中でフォルダー提示を通った: \(targets)")
    }
}
