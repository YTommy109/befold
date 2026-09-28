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
            resizable: false,
            placement: .centered
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
            placement: .centered,
            contentSize: NSSize(width: 480, height: 420),
            minSize: NSSize(width: 400, height: 320)
        )

        #expect(controller.window?.styleMask.contains(.resizable) == true)
        #expect(controller.window?.minSize == NSSize(width: 400, height: 320))
        controller.window?.close()
    }

    // MARK: - 開く位置(TASK-656)

    /// frame autosave は standard の UserDefaults に書かれるため、テストごとに一意な名前を使い後始末する。
    private static func uniqueAutosaveName() -> String {
        "HostedPanelWindowControllerTests-\(UUID().uuidString)"
    }

    private static func removeSavedFrame(_ name: String) {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    }

    private func makeResizable(placement: HostedPanelPlacement) -> HostedPanelWindowController {
        HostedPanelWindowController(
            rootView: FeatureOverviewView(),
            title: "Placement",
            resizable: true,
            placement: placement,
            contentSize: NSSize(width: 480, height: 420),
            minSize: NSSize(width: 400, height: 320)
        )
    }

    /// 中央以外であることが確実に分かる位置へ動かして閉じ、同名で作り直した窓の枠を返す。
    private func reopenedFrame(after moved: NSRect, placement: HostedPanelPlacement) -> NSRect? {
        let first = makeResizable(placement: placement)
        first.showAndActivate()
        first.window?.setFrame(moved, display: false)
        first.window?.close()

        let second = makeResizable(placement: placement)
        second.showAndActivate()
        defer { second.window?.close() }
        return second.window?.frame
    }

    @Test("rememberFrame は最後の位置とサイズで開き直す")
    func rememberFrameRestoresPositionAndSize() {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let moved = NSRect(x: 40, y: 60, width: 610, height: 450)

        let frame = reopenedFrame(after: moved, placement: .rememberFrame(autosaveName: name))

        #expect(frame == moved)
    }

    @Test("同じ起動中に閉じて開き直しても中央へ戻さない")
    func rememberFrameKeepsPositionAcrossToggleInSession() {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let controller = makeResizable(placement: .rememberFrame(autosaveName: name))
        controller.showAndActivate()
        let moved = NSRect(x: 40, y: 60, width: 610, height: 450)
        controller.window?.setFrame(moved, display: false)
        controller.window?.close()

        controller.showAndActivate()
        defer { controller.window?.close() }

        #expect(controller.window?.frame == moved)
    }

    @Test("rememberPosition は左上だけを復元し、サイズは生成時のまま")
    func rememberPositionRestoresOnlyTopLeft() {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let moved = NSRect(x: 40, y: 60, width: 610, height: 450)
        let initialSize = makeResizable(placement: .centered).window?.frame.size

        let frame = reopenedFrame(after: moved, placement: .rememberPosition(autosaveName: name))

        #expect(frame?.size == initialSize)
        #expect(frame?.minX == moved.minX)
        #expect(frame?.maxY == moved.maxY)
    }

    @Test("保存値が無い初回は中央に開く")
    func rememberFrameCentersWithoutSavedFrame() {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let expected = makeResizable(placement: .centered)
        expected.showAndActivate()
        defer { expected.window?.close() }

        let controller = makeResizable(placement: .rememberFrame(autosaveName: name))
        controller.showAndActivate()
        defer { controller.window?.close() }

        #expect(controller.window?.frame == expected.window?.frame)
    }

    @Test("centered は動かしても開くたびに中央へ戻す")
    func centeredRecentersOnEveryShow() {
        let controller = makeResizable(placement: .centered)
        controller.showAndActivate()
        let centered = controller.window?.frame
        controller.window?.setFrameOrigin(NSPoint(x: 40, y: 60))
        controller.window?.close()

        controller.showAndActivate()
        defer { controller.window?.close() }

        #expect(controller.window?.frame == centered)
    }

    @Test("パネルごとの方針: ブックマークは位置とサイズ、設定は位置だけ、読むだけのパネルは中央")
    func placementPerPanel() {
        #expect(HostedPanel.bookmarks.placement.keepsSize)
        #expect(HostedPanel.bookmarks.placement.autosaveName != nil)
        #expect(!HostedPanel.settings.placement.keepsSize)
        #expect(HostedPanel.settings.placement.autosaveName != nil)
        #expect(HostedPanel.bookmarks.placement.autosaveName != HostedPanel.settings.placement.autosaveName)
        let readOnly: [HostedPanel] = [.about, .featureOverview, .keyboardShortcuts, .aiIntegration, .ossLicenses]
        for panel in readOnly {
            #expect(panel.placement == .centered, "\(panel)")
        }
    }
}
