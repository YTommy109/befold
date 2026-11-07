import AppKit
@testable import befold
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
            onSidebarDidHide: {}
        )

        #expect(controller.resolvedSidebarCollapsed == initialCollapsed)
    }
}
