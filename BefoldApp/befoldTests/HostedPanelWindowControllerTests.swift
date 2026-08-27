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
            rootView: SettingsView(
                preference: CodeFontPreference(defaults: defaults),
                onChange: {},
                numberPreference: CsvNumberFormatPreference(defaults: defaults),
                onNumberChange: {}
            ),
            title: "Settings",
            resizable: false
        )
    }

    /// 設定窓は resizable: false で、中身の固有サイズがそのまま窓幅になる。
    /// コードフォントと数値表示の Section が別物として見分けられる幅を保つための
    /// 回帰テスト(TASK-557.2)。狭めると Picker のラベルと選択肢が詰まって
    /// どちらの Section の設定か読み取りにくくなる。
    @Test("設定窓は Section を見分けられる幅を持つ")
    func settingsWindowIsWideEnoughForSections() {
        let controller = makeController()
        controller.showAndActivate()
        defer { controller.window?.close() }

        let width = controller.window?.contentView?.fittingSize.width ?? 0
        #expect(width >= 460)
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
