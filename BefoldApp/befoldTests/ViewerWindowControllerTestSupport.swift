import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation

/// ViewerWindowControllerDelegate の通知を記録するスタブ。
/// 差分トグルの検証(ViewerWindowControllerDiffTests)や、
/// ViewerWindowControllerTests から分割した各スイートからも使うため、
/// スイート内 private にせず befoldTests 内で共有する。
final class MockViewerWindowControllerDelegate: ViewerWindowControllerDelegate {
    var becomeKeyCalled = false
    var closeCalled = false
    var renameArgs: (old: URL, new: URL)?
    var switchFileArgs: (old: URL, new: URL)?
    var toggleHiddenFilesCalled = false
    var toggleChangedFilesOnlyCalled = false
    /// 差分レイアウト切替の通知回数。全ウィンドウのツールバー再同期がこの通知に
    /// 乗っているため、「切り替えたのに通知されない」= アイコンが取り残される。
    private(set) var diffLayoutToggleCount = 0
    private(set) var toggleSidebarTreeLayoutCalled = false
    /// リサイズ確定で通知されたフレーム記述子。閉じたときには通知されないことも見る(TASK-583)。
    private(set) var adjustedFrameDescriptors: [String] = []

    func viewerWindowWillClose(_ controller: ViewerWindowController) {
        closeCalled = true
    }

    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController) {
        becomeKeyCalled = true
    }

    func viewerWindow(_ controller: ViewerWindowController, didAdjustFrameTo descriptor: String) {
        adjustedFrameDescriptors.append(descriptor)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL
    ) {
        renameArgs = (oldURL, newURL)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    ) {
        switchFileArgs = (oldURL, newURL)
    }

    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController) {
        toggleHiddenFilesCalled = true
    }

    func viewerWindowDidToggleDiffLayout(_ controller: ViewerWindowController) {
        diffLayoutToggleCount += 1
    }

    func viewerWindowDidToggleChangedFilesOnly(_ controller: ViewerWindowController) {
        toggleChangedFilesOnlyCalled = true
    }

    func viewerWindowDidToggleSidebarTreeLayout(_ controller: ViewerWindowController) {
        toggleSidebarTreeLayoutCalled = true
    }
}

/// 複数ファイルを InMemoryFileReader に登録した store を持つコントローラーを作る。
/// primary が初期表示ファイル、others は switch/リンク先として存在確認を通すために登録する。
///
/// 切替・履歴・参照解決の各スイート(ViewerWindowControllerFileSwitchTests /
/// ViewerWindowControllerHistoryTests / ViewerWindowControllerRefResolutionTests /
/// ViewerWindowControllerReferenceOpenTests)が共有するため、
/// Swift の private がファイルスコープであることを踏まえてここへ internal で置く。
@MainActor
func makeMockedViewerWindowController(
    primary: URL,
    others: [URL] = [],
    contents: String = "graph TD;",
    zoomStore: ZoomStore? = nil,
    defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"),
    openFileElsewhere: @escaping (URL, OpenDisposition, NSWindow?) -> Void = { _, _, _ in },
    externalOpener: @escaping (URL) -> Void = { _ in }
) -> ViewerWindowController {
    ViewerWindowControllerFixture(
        file: primary,
        extraFiles: others,
        contents: contents,
        defaults: defaults,
        zoomStore: zoomStore,
        openFileElsewhere: openFileElsewhere,
        externalOpener: externalOpener
    ).controller
}
