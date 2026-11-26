@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// Quick Open で別フォルダーのファイルを開いたときに、サイドバーの選択が着地を待たずに
/// 新しいファイルへ確定することの回帰テスト(TASK-445)。
///
/// 本文の提示はサイドバーから導かなくなった(ADR 0013。検証は
/// `ViewerWindowFileOpenPresentationTests`)。ここで守るのはサイドバー側の不変条件、
/// 「切替の同期区間で選択が確定する」こと。着地に委ねると、世代の追い越しで着地しなければ
/// 強調が旧行に残り続ける。
///
/// 一覧の取得はここでは**決して着地させない**(AsyncGate を開けない)。着地に依存せず
/// 選択が決まることがこのスイートの検証点で、着地させてしまうと後追いの選択確定に
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
    @Test("フォルダー選択中に別フォルダーのファイルへ切り替えると、着地を待たずに選択が確定する")
    func switchFromFolderSelectionLeavesFolderPresentation() async {
        let gate = AsyncGate()
        let fixture = makeFixture(gate: gate)
        let navigator = fixture.navigator
        defer { withExtendedLifetime(fixture.host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.fileListModel.selection = fixture.sub

        _ = fixture.host.performFileSwitch(to: fixture.target)
        navigator.syncAfterSwitch(to: fixture.target)

        // 一覧はまだ届いていない。それでも選択は新しいファイルへ確定していなければならない。
        #expect(navigator.fileListModel.selection?.normalizedPathKey == fixture.target.normalizedPathKey)
    }

    /// 選択が無い(navigateToFolder 直後など)状態からでも同じであること(AC #1)。
    @Test("選択が無い状態から別フォルダーのファイルへ切り替えると、着地を待たずに選択が確定する")
    func switchFromNoSelectionLeavesFolderPresentation() async {
        let gate = AsyncGate()
        let fixture = makeFixture(gate: gate)
        let navigator = fixture.navigator
        defer { withExtendedLifetime(fixture.host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        navigator.fileListModel.selection = nil

        _ = fixture.host.performFileSwitch(to: fixture.target)
        navigator.syncAfterSwitch(to: fixture.target)

        #expect(navigator.fileListModel.selection?.normalizedPathKey == fixture.target.normalizedPathKey)
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

        #expect(navigator.fileListModel.selection?.normalizedPathKey == sibling.normalizedPathKey)
    }
}
