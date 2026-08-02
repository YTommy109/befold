import AppKit
@testable import befold
import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// パス無し CLI 転送(`befold --line-numbers` 等)で開いている既存ウィンドウへ
/// 行番号/ソース表示/並び順/サイドバー開閉のオーバーライドが反映されることを検証する。
/// コントローラ生成は MockedViewerWindowManager 経由でモック化しているため実 FS を踏まない。
/// サイドバー entries の並び替え結果そのものを見る検証は
/// ViewerWindowManagerDisplayOverridesIntegrationTests に残している。
@Suite
@MainActor
struct ViewerWindowManagerDisplayOverridesTests {
    private let file = URL(fileURLWithPath: "/mock/first.mmd")
    private let markdownFile = URL(fileURLWithPath: "/mock/second.md")

    @Test("開いている全ウィンドウへ行番号/ソース/並び順を反映する")
    func applyDisplayOverridesAffectsAllOpenWindows() {
        let fixture = MockedViewerWindowManager(
            files: [file, markdownFile], prefix: "ViewerWindowManagerDisplayOverridesTests"
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: markdownFile)

        fixture.manager.applyDisplayOverrides(
            CLIOpenOptions(sortOrder: .alphabetical, showLineNumbers: true, sourceMode: true)
        )

        for controller in fixture.manager.allControllers {
            #expect(controller.store.showLineNumbers)
            #expect(controller.isSourceMode)
            #expect(controller.fileListModel.sortOrder == .alphabetical)
        }
    }

    @Test("nil を渡したオーバーライドは既存ウィンドウの状態を変更しない")
    func applyDisplayOverridesLeavesUnspecifiedOptionsUntouched() throws {
        let fixture = MockedViewerWindowManager(
            files: [file], prefix: "ViewerWindowManagerDisplayOverridesTests"
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        let originalSortOrder = controller.fileListModel.sortOrder
        let originalSourceMode = controller.isSourceMode

        fixture.manager.applyDisplayOverrides(CLIOpenOptions(showLineNumbers: true))

        #expect(controller.store.showLineNumbers)
        #expect(controller.isSourceMode == originalSourceMode)
        #expect(controller.fileListModel.sortOrder == originalSortOrder)
    }

    @Test("行番号オーバーライドは既存ウィンドウのツールバーアイテムへも反映される")
    func applyDisplayOverridesRefreshesLineNumbersToolbarItem() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "LineNumbersToolbarRefresh")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        let toolbar = try #require(controller.window?.toolbar)
        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("lineNumbers") })
        let button = try #require(liveItem.view as? NSButton)
        #expect(button.contentTintColor == nil)

        // sourceMode を渡さず行番号のみを上書きする(間接発火に頼れない経路)。
        fixture.manager.applyDisplayOverrides(CLIOpenOptions(showLineNumbers: true))

        #expect(button.contentTintColor == .controlAccentColor)
    }

    @Test(
        "新規ウィンドウは options.showSidebar に従って開閉状態が決まる",
        arguments: [(true, false), (false, true)]
    )
    func sidebarVisibleOverrideDeterminesInitialCollapse(visible: Bool, expectedCollapsed: Bool) {
        let fixture = MockedViewerWindowManager(
            files: [file], prefix: "SidebarOverrideInitial-\(visible)"
        )
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showSidebar: visible))

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == expectedCollapsed)
    }

    @Test("showSidebar 未指定(nil)なら保存済み開閉状態を維持する")
    func sidebarVisibleOverrideNilKeepsSavedState() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SidebarOverrideNil")
        defer { fixture.closeAll() }
        // 事前に「開いた状態(collapsed=false)」を保存しておく。
        fixture.perFileState.sidebar.setCollapsed(false, for: file)

        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showSidebar: nil))

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
    }

    @Test("既存ウィンドウへ showSidebar を反映して開閉状態を切り替える")
    func applyDisplayOverridesTogglesSidebarOnOpenWindow() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SidebarOverrideApply")
        defer { fixture.closeAll() }
        // 閉じた状態で開く。
        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showSidebar: false))
        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == true)

        fixture.manager.applyDisplayOverrides(CLIOpenOptions(showSidebar: true))

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
    }
}
