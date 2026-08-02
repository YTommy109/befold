import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 単一インスタンスのパネルウィンドウ(About・設定・Help 配下)が共有する開閉トグルを検証する。
/// 実ウィンドウの最前面判定は isFrontmost シームで置き換える。
/// 中身のビューは設定画面(依存注入があり構築が最も重い)で代表させる。
@MainActor
@Suite
struct HostedPanelWindowControllerTests {
    private func makeController() -> HostedPanelWindowController {
        let defaults = makeIsolatedDefaults(prefix: "HostedPanelWindowControllerTests")
        return HostedPanelWindowController(
            rootView: CodeFontSettingsView(
                preference: CodeFontPreference(defaults: defaults),
                onChange: {}
            ),
            title: "Settings",
            resizable: false
        )
    }

    @Test("未表示から toggle すると表示される")
    func togglePresentsWhenClosed() {
        let controller = makeController()
        controller.isFrontmost = { false }

        controller.toggle()

        #expect(controller.window?.isVisible == true)
        controller.window?.close()
    }

    @Test("最前面から toggle すると閉じる")
    func toggleClosesWhenFrontmost() {
        let controller = makeController()
        controller.showAndActivate()
        controller.isFrontmost = { true }

        controller.toggle()

        #expect(controller.window?.isVisible == false)
    }

    @Test("表示中だが最前面でない場合、toggle すると前面化されて閉じない")
    func toggleActivatesWhenNotFrontmost() {
        let controller = makeController()
        controller.showAndActivate()
        controller.isFrontmost = { false }

        controller.toggle()

        #expect(controller.window?.isVisible == true)
        controller.window?.close()
    }

    @Test("resizable: false のウィンドウはリサイズできない")
    func nonResizablePanelHasNoResizeStyle() {
        let controller = makeController()

        #expect(controller.window?.styleMask.contains(.resizable) == false)
        controller.window?.close()
    }

    @Test("resizable: true ならリサイズでき、指定したサイズが反映される")
    func resizablePanelAppliesRequestedSizes() {
        let controller = HostedPanelWindowController(
            rootView: FeatureOverviewView(),
            title: "Feature Overview",
            resizable: true,
            contentSize: NSSize(width: 480, height: 420),
            minSize: NSSize(width: 400, height: 320)
        )

        #expect(controller.window?.styleMask.contains(.resizable) == true)
        #expect(controller.window?.minSize == NSSize(width: 400, height: 320))
        controller.window?.close()
    }
}
