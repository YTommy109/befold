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
    private func makeController(placement: HostedPanelPlacement = .centered) -> HostedPanelWindowController {
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
            placement: placement
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

    // MARK: - 開く位置(TASK-656 / TASK-658)

    // 位置はリテラルで決めず、期待値もリテラルで書かない。AppKit は保存値を画面構成に合わせて
    // 補正するため、手元と CI で結果が変わる(.claude/CLAUDE.md「環境に依存する実測値をアサートしない」)。
    // 移動先は可視領域から作り、期待値は同じ実行中に AppKit が実際に採った枠を使う。

    private static let autosavePrefix = "HostedPanelWindowControllerTests-"

    /// テストごとに一意な保存名を返す。frame autosave は standard の UserDefaults に書かれ、
    /// Xcode のテストホスト(befold.app)ではインストール版と同じ領域になる。途中で落ちた回の
    /// 値が残らないよう、ここで同じ接頭辞の古い値を掃除する。テストはどれも @MainActor の
    /// 同期テストで互いに割り込まないため、実行中の他のテストの値を消すことはない。
    private static func uniqueAutosaveName() -> String {
        let defaults = UserDefaults.standard
        let stalePrefix = "NSWindow Frame \(autosavePrefix)"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(stalePrefix) {
            defaults.removeObject(forKey: key)
        }
        return autosavePrefix + UUID().uuidString
    }

    private static func removeSavedFrame(_ name: String) {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    }

    /// 表示直後(中央)の窓を可視領域の左上寄りへ動かし、AppKit が実際に採った枠を返す。
    /// `resize` なら少し大きくもする。動かした先が中央と区別できることを前提として確かめる。
    private static func moveAwayFromCenter(_ window: NSWindow, resize: Bool) throws -> NSRect {
        let centered = window.frame
        let visible = try #require(window.screen?.visibleFrame)
        let size = resize ? NSSize(width: centered.width + 60, height: centered.height + 30) : centered.size
        let origin = NSPoint(x: visible.minX + 40, y: visible.maxY - 40 - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        try #require(window.frame.origin != centered.origin)
        return window.frame
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

    @Test("リサイズ可能な窓は最後の位置とサイズで開き直す")
    func rememberRestoresPositionAndSizeOfResizableWindow() throws {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let first = makeResizable(placement: .remember(autosaveName: name))
        first.showAndActivate()
        let window = try #require(first.window)
        let left = try Self.moveAwayFromCenter(window, resize: true)
        window.close()

        let second = makeResizable(placement: .remember(autosaveName: name))
        second.showAndActivate()
        defer { second.window?.close() }

        #expect(second.window?.frame == left)
    }

    @Test("同じ起動中に閉じて開き直しても中央へ戻さない")
    func rememberKeepsPositionAcrossToggleInSession() throws {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let controller = makeResizable(placement: .remember(autosaveName: name))
        controller.showAndActivate()
        let window = try #require(controller.window)
        let left = try Self.moveAwayFromCenter(window, resize: true)
        window.close()

        controller.showAndActivate()
        defer { window.close() }

        #expect(window.frame == left)
    }

    /// 設定窓と同じ構成(SettingsView・resizable: false・contentSize なし)で確かめる。
    /// リサイズ不可の窓では AppKit が保存値の左上だけを戻し、サイズは中身に従う(TASK-657)。
    @Test("設定窓の構成では最後の位置で開き、サイズは中身のまま")
    func rememberRestoresOnlyPositionOfSettingsWindow() throws {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let first = makeController(placement: .remember(autosaveName: name))
        first.showAndActivate()
        let window = try #require(first.window)
        let fittedSize = window.frame.size
        let left = try Self.moveAwayFromCenter(window, resize: false)
        window.close()

        let second = makeController(placement: .remember(autosaveName: name))
        second.showAndActivate()
        defer { second.window?.close() }

        let frame = try #require(second.window?.frame)
        #expect(frame.size == fittedSize)
        #expect(frame.minX == left.minX)
        #expect(frame.maxY == left.maxY)
    }

    @Test("保存値が無い初回は中央に開く")
    func rememberCentersWithoutSavedFrame() throws {
        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }
        let controller = makeResizable(placement: .remember(autosaveName: name))
        controller.showAndActivate()
        let window = try #require(controller.window)
        defer { window.close() }

        // 中央に置かれていれば、中央寄せをやり直しても枠は変わらない。
        let shown = window.frame
        window.center()
        #expect(window.frame == shown)
    }

    @Test("centered は動かしても開くたびに中央へ戻す")
    func centeredRecentersOnEveryShow() throws {
        let controller = makeResizable(placement: .centered)
        controller.showAndActivate()
        let window = try #require(controller.window)
        let centered = window.frame
        _ = try Self.moveAwayFromCenter(window, resize: false)
        window.close()

        controller.showAndActivate()
        defer { window.close() }

        #expect(window.frame == centered)
    }

    @Test("途中で落ちた回の保存値は、次のテストの開始時に掃除される")
    func staleSavedFramesAreSweptOnNextName() {
        let stale = "NSWindow Frame \(Self.autosavePrefix)stale"
        UserDefaults.standard.set("0 0 100 100 0 0 1000 1000 ", forKey: stale)
        defer { UserDefaults.standard.removeObject(forKey: stale) }

        let name = Self.uniqueAutosaveName()
        defer { Self.removeSavedFrame(name) }

        #expect(UserDefaults.standard.object(forKey: stale) == nil)
    }

    @Test("パネルごとの方針: ブックマークと設定は枠を覚え、読むだけのパネルは中央")
    func placementPerPanel() {
        #expect(HostedPanel.bookmarks.placement == .remember(autosaveName: "BookmarkManagerWindow"))
        #expect(HostedPanel.settings.placement == .remember(autosaveName: "SettingsWindow"))
        let readOnly: [HostedPanel] = [.about, .featureOverview, .keyboardShortcuts, .aiIntegration, .ossLicenses]
        for panel in readOnly {
            #expect(panel.placement == .centered, "\(panel)")
        }
    }
}
