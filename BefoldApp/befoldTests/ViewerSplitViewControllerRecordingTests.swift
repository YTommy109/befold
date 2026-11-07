import AppKit
@testable import befold
import BefoldTestSupport
import SwiftUI
import Testing

/// 開閉のうち、保存値へ記録するのは利用者の操作だけであること(ADR 0002「窓の状態」)。
/// 実物の `NSSplitViewItem` を動かすため、非表示の窓へ載せる(表示前は AppKit へ到達すると落ちる)。
@Suite
@MainActor
struct ViewerSplitViewControllerRecordingTests {
    final class Recorded {
        var values: [Bool] = []
    }

    private func makeHosted(
        initialCollapsed: Bool, recorded: Recorded
    ) -> (NSWindow, ViewerSplitViewController<EmptyView, EmptyView>) {
        let controller = ViewerSplitViewController(
            sidebar: EmptyView(), content: EmptyView(), initialCollapsed: initialCollapsed,
            onCollapsedChange: { recorded.values.append($0) },
            onSidebarDidReveal: {},
            onSidebarDidHide: {}
        )
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        return (window, controller)
    }

    @Test("CLI とフォルダーオープンの開閉は記録せず、利用者の操作だけを記録する")
    func onlyUserTogglesAreRecorded() {
        let recorded = Recorded()
        let (window, controller) = makeHosted(initialCollapsed: false, recorded: recorded)
        defer { window.close() }
        let current = controller.isSidebarCollapsed

        controller.setSidebarCollapsed(!current)
        #expect(controller.isSidebarCollapsed == !current)
        #expect(recorded.values.isEmpty)

        controller.toggleSidebar(nil)
        #expect(recorded.values == [current])
    }

    /// 背面のタブは viewWillAppear が来ないまま起点になる(複数ファイルのドロップ)。
    /// 表示前の `isCollapsed` を読むと、閉じているはずの窓が開いているものとして引き継がれる。
    @Test("表示前の窓は初期値を開閉状態として返す", arguments: [true, false])
    func resolvedStateBeforeAppearanceIsInitialValue(initialCollapsed: Bool) {
        let controller = ViewerSplitViewController(
            sidebar: EmptyView(), content: EmptyView(), initialCollapsed: initialCollapsed,
            onCollapsedChange: { _ in }, onSidebarDidReveal: {}, onSidebarDidHide: {}
        )

        #expect(controller.resolvedSidebarCollapsed == initialCollapsed)
    }

    /// 文書タブと空タブが共有する配線(TASK-920)。コールバックを取り違えても既存のテストは
    /// 通ってしまうので、組み立て関数そのものを測る。開閉の初期状態は autosave に左右されるので、
    /// 記録しない `setSidebarCollapsed` で先に決める。待つのはキュー 1 回分だけにし、配線が
    /// 外れたら時間切れではなくその場で落とす。
    @Test("共通の組み立ては開閉を記録し、開くとフォーカスを要求し、畳むと要求を捨てる", testTimeLimit())
    func sharedAssemblyWiresRecordingAndFocus() async {
        let defaults = makeIsolatedDefaults(prefix: "ViewerSplitViewControllerRecordingTests.shared")
        let sidebarState = SidebarStateStore(defaults: defaults)
        let model = FileListModel(currentDirectory: URL(fileURLWithPath: "/mock"), entries: [], selection: nil)
        let delegate = FileListViewDelegateSpy()
        let controller = ViewerWindowAssembler.makeSidebarSplit(
            sidebar: FileListView(model: model, delegate: delegate), content: EmptyView(),
            initialCollapsed: true, allowsSidebar: true, sidebarState: sidebarState
        )
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = controller
        controller.setSidebarCollapsed(true)
        #expect(controller.isSidebarCollapsed)

        controller.toggleSidebar(nil)
        #expect(!sidebarState.lastToggledCollapsed)
        await Self.drainMainQueue()
        #expect(model.tableFocuser.focusPending, "開いてもフォーカスを要求しなかった")

        controller.toggleSidebar(nil)
        #expect(sidebarState.lastToggledCollapsed)
        #expect(!model.tableFocuser.focusPending, "畳んでも保留中の要求が残った")
    }

    /// 開いた通知は `DispatchQueue.main.async` で届く。同じキューへ積んで、その後ろまで進める。
    private static func drainMainQueue() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
}
