import AppKit
@testable import befold
import BefoldKit
import SwiftUI
import Testing

/// スライド窓（`ViewerWindowKind.slide`）の性質を、GUI を起動せずに測れる範囲で固定する
/// (TASK-593.2)。
///
/// **窓そのものの見た目（ツールバーが出ない・タブに合流しない）は自動テスト対象外**なので、
/// ここで測るのは「種別が述語として何を意味するか」と「述語を読む側が種別どおりに振る舞うか」。
@MainActor
struct ViewerWindowKindTests {
    @Test("通常のビューア窓はサイドバー・ツールバー・タブ・復元のすべてを持つ")
    func viewerKindAllowsEverything() {
        let kind = ViewerWindowKind.viewer

        #expect(kind.allowsSidebar)
        #expect(kind.hasToolbar)
        #expect(kind.joinsTabs)
        #expect(kind.isRestorable)
    }

    @Test("スライド窓はサイドバー・ツールバー・タブ・復元のすべてを持たない")
    func slideKindAllowsNothing() {
        let kind = ViewerWindowKind.slide

        #expect(!kind.allowsSidebar)
        #expect(!kind.hasToolbar)
        #expect(!kind.joinsTabs)
        #expect(!kind.isRestorable)
    }
}

/// スライド窓でサイドバーが開かないことの担保。
///
/// 開閉の経路は 3 本ある——⌘S（メニュー）・⌘←（フォーカス移動）・`setSidebarCollapsed(_:)`
/// （CLI の `--sidebar` と `forceSidebarVisible` がここへ来る）。メニュー側の 2 本は
/// `ViewerMenuValidatorTests` が測り、ここでは**実際に開かせない側**——
/// `ViewerSplitViewController.toggleSidebar(_:)` の早期 return——を測る。
/// `setSidebarCollapsed(_:)` は `toggleSidebar` を呼ぶので同じ 1 箇所を通る。
///
/// **ウィンドウへ載せない。** `NSSplitViewItem.isCollapsed` の代入は AppKit が
/// `NSSplitView` の subview 配列を触るため、表示していないコントローラでは落ちる
/// （実測: `NSRangeException` / SIGSEGV）。逆に言うと、ここが AppKit へ到達しないことが
/// 早期 return が効いていることの証拠になる——ガードを外すと**このテストが落ちる**。
/// 通常の窓で従来どおり開くことは GUI 層なので `/run` の目視で確かめる（テスト規約）。
@MainActor
struct SlideWindowSidebarGuardTests {
    /// `onCollapsedChange` の発火を数える入れ物。本番ではこのクロージャが
    /// `SidebarStateStore.recordToggle` を呼ぶ唯一の経路なので、発火しないことが
    /// 「保存値を汚さない」ことの担保になる。
    @MainActor
    final class RecordedToggles {
        var values: [Bool] = []
    }

    private func makeSlideSplitViewController(
        recordedToggles: RecordedToggles
    ) -> ViewerSplitViewController<EmptyView, EmptyView> {
        ViewerSplitViewController(
            sidebar: EmptyView(), content: EmptyView(),
            initialCollapsed: true,
            allowsSidebar: false,
            onCollapsedChange: { collapsed in recordedToggles.values.append(collapsed) },
            onSidebarDidHide: {}
        )
    }

    @Test("スライド窓では toggleSidebar が AppKit の開閉へ到達しない")
    func toggleSidebarReturnsEarly() {
        let toggles = RecordedToggles()
        let controller = makeSlideSplitViewController(recordedToggles: toggles)

        controller.toggleSidebar(nil)

        #expect(toggles.values.isEmpty)
    }

    /// `setSidebarCollapsed(_:)` は「現在と違うときだけ `toggleSidebar` を呼ぶ」実装なので、
    /// **現在と違う値を渡す**こと。同じ値だと自身の早期 return で止まり、
    /// `allowsSidebar` のガードを一度も通らないまま緑になる。
    @Test("スライド窓では setSidebarCollapsed も同じガードで止まる")
    func setSidebarCollapsedReturnsEarly() {
        let toggles = RecordedToggles()
        let controller = makeSlideSplitViewController(recordedToggles: toggles)
        #expect(!controller.isSidebarCollapsed, "この時点では viewWillAppear 前で畳まれていない")

        controller.setSidebarCollapsed(true)

        #expect(toggles.values.isEmpty)
    }
}
