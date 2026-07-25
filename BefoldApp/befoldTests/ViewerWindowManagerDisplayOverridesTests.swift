import AppKit
@testable import befold
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
        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: markdownFile)

        fixture.manager.applyDisplayOverrides(
            showLineNumbers: true, sourceMode: true, sortOrder: .alphabetical, showSidebar: nil
        )

        for controller in fixture.manager.controllers.values {
            #expect(controller.store.showLineNumbers)
            #expect(controller.isSourceMode)
            #expect(controller.fileListModel.sortOrder == .alphabetical)
        }
        fixture.closeAll()
    }

    @Test("nil を渡したオーバーライドは既存ウィンドウの状態を変更しない")
    func applyDisplayOverridesLeavesUnspecifiedOptionsUntouched() throws {
        let fixture = MockedViewerWindowManager(
            files: [file], prefix: "ViewerWindowManagerDisplayOverridesTests"
        )
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey])
        let originalSortOrder = controller.fileListModel.sortOrder
        let originalSourceMode = controller.isSourceMode

        fixture.manager.applyDisplayOverrides(
            showLineNumbers: true, sourceMode: nil, sortOrder: nil, showSidebar: nil
        )

        #expect(controller.store.showLineNumbers)
        #expect(controller.isSourceMode == originalSourceMode)
        #expect(controller.fileListModel.sortOrder == originalSortOrder)
        fixture.closeAll()
    }

    @Test("行番号オーバーライドは既存ウィンドウのツールバーアイテムへも反映される")
    func applyDisplayOverridesRefreshesLineNumbersToolbarItem() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "LineNumbersToolbarRefresh")
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey])
        let toolbar = try #require(controller.window?.toolbar)
        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("lineNumbers") })
        let button = try #require(liveItem.view as? NSButton)
        #expect(button.contentTintColor == nil)

        // sourceMode を渡さず行番号のみを上書きする(間接発火に頼れない経路)。
        fixture.manager.applyDisplayOverrides(
            showLineNumbers: true, sourceMode: nil, sortOrder: nil, showSidebar: nil
        )

        #expect(button.contentTintColor == .controlAccentColor)
        fixture.closeAll()
    }

    @Test(
        "新規ウィンドウは sidebarVisibleOverride に従って開閉状態が決まる",
        arguments: [(true, false), (false, true)]
    )
    func sidebarVisibleOverrideDeterminesInitialCollapse(visible: Bool, expectedCollapsed: Bool) {
        let fixture = MockedViewerWindowManager(
            files: [file], prefix: "SidebarOverrideInitial-\(visible)"
        )

        fixture.manager.openViewer(for: file, sidebarVisibleOverride: visible)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == expectedCollapsed)
        fixture.closeAll()
    }

    @Test("sidebarVisibleOverride 未指定(nil)なら保存済み開閉状態を維持する")
    func sidebarVisibleOverrideNilKeepsSavedState() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SidebarOverrideNil")
        // 事前に「開いた状態(collapsed=false)」を保存しておく。
        fixture.perFileState.sidebar.setCollapsed(false, for: file)

        fixture.manager.openViewer(for: file, sidebarVisibleOverride: nil)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
        fixture.closeAll()
    }

    @Test("既存ウィンドウへ showSidebar を反映して開閉状態を切り替える")
    func applyDisplayOverridesTogglesSidebarOnOpenWindow() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SidebarOverrideApply")
        // 閉じた状態で開く。
        fixture.manager.openViewer(for: file, sidebarVisibleOverride: false)
        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == true)

        fixture.manager.applyDisplayOverrides(
            showLineNumbers: nil, sourceMode: nil, sortOrder: nil, showSidebar: true
        )

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
        fixture.closeAll()
    }
}
