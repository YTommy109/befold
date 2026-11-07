import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// 空タブのサイドバー。開閉と一覧の起点は窓の状態(ADR 0002)で、文書タブの間で変わらない。
@Suite
@MainActor
struct BlankTabSidebarTests {
    private let first = URL(fileURLWithPath: "/mock/folder/first.md")
    private let second = URL(fileURLWithPath: "/mock/folder/second.md")

    private func makeSource(
        in fixture: MockedViewerWindowManager, collapsed: Bool
    ) throws -> (window: NSWindow, sidebar: RecordingSidebarCollapsible) {
        let controller = try #require(fixture.manager.openViewer(for: first))
        let sidebar = RecordingSidebarCollapsible()
        sidebar.resolvedSidebarCollapsed = collapsed
        controller.sidebarCollapsible = sidebar
        return try (#require(controller.window), sidebar)
    }

    @Test("空タブは起点の窓の開閉状態とフォルダを引き継ぐ", arguments: [true, false])
    func inheritsCollapseAndFolderFromSource(collapsed: Bool) async throws {
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: collapsed)
        fixture.sidebarState.recordToggle(!collapsed)

        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }

        #expect(blank.sidebarCollapsible?.resolvedSidebarCollapsed == collapsed)
        let navigator = try #require(blank.inheritableSidebar)
        await navigator.awaitSettled()
        let model = navigator.fileListModel
        #expect(model.currentDirectory.normalizedPathKey == first.deletingLastPathComponent().normalizedPathKey)
        #expect(model.selection == nil)
        withExtendedLifetime(source.sidebar) {}
    }

    @Test("サイドバーのある空タブはツールバーに文書タブと同じ区切りを持つ")
    func toolbarMatchesDocumentTab() throws {
        let fixture = MockedViewerWindowManager(files: [first])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)

        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }

        let toolbar = try #require(blank.window?.toolbar)
        #expect(toolbar.items.map(\.itemIdentifier) == ViewerToolbarController.layout.map(\.identifier))
        withExtendedLifetime(source.sidebar) {}
    }

    /// 列挙するフォルダが決まらないので、サイドバーそのものを持たない。
    @Test("起点の窓が無い空タブはサイドバーを持たない")
    func noSourceHasNoSidebar() {
        let fixture = MockedViewerWindowManager(files: [])
        defer { fixture.closeAll() }

        let blank = fixture.manager.blankTabs.open(relativeTo: nil)
        defer { blank.close() }

        #expect(blank.inheritableSidebar == nil)
        #expect(blank.sidebarCollapsible == nil)
    }

    @Test("空タブを起点にしても次の空タブが開閉とフォルダを引き継ぐ")
    func blankTabCanBeTheSourceOfAnotherBlankTab() throws {
        let fixture = MockedViewerWindowManager(files: [first])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }

        let next = fixture.manager.blankTabs.open(relativeTo: blank.window)
        defer { next.close() }

        #expect(next.sidebarCollapsible?.resolvedSidebarCollapsed == false)
        #expect(next.window?.tabGroup === source.window.tabGroup)
        #expect(
            next.inheritableSidebar?.fileListModel.currentDirectory.normalizedPathKey
                == first.deletingLastPathComponent().normalizedPathKey
        )
        withExtendedLifetime(source.sidebar) {}
    }

    /// 空タブにはフォーカスを取る部品が無く、first responder は窓自身になる。⌘S とツールバーの
    /// ボタンは宛先なしのアクションなので、窓から split view へ届くことを測る(TASK-915)。
    /// `toggleSidebar` を直接呼ぶテストはこの経路を通らない。
    @Test("空タブの窓が受けたサイドバーの開閉が split view へ届き、利用者の操作として記録される")
    func sidebarToggleFromWindowReachesSplitView() throws {
        let fixture = MockedViewerWindowManager(files: [first])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: true)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }
        let window = try #require(blank.window)
        #expect(window.firstResponder === window)
        #expect(blank.sidebarCollapsible?.isSidebarCollapsed == true)
        // ⌘S とツールバーのボタンが灰色にならないこと。宛先なしのアクションは first responder
        // (ここでは窓)の検証を通る。テストの窓はキーにならないので、検証は窓へ直接問う。
        let item = NSMenuItem(title: "", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "")
        #expect(window.validateUserInterfaceItem(item))

        let handled = NSApp.sendAction(
            #selector(NSSplitViewController.toggleSidebar(_:)), to: window.firstResponder, from: nil
        )

        #expect(handled)
        #expect(blank.sidebarCollapsible?.isSidebarCollapsed == false)
        #expect(!fixture.sidebarState.lastToggledCollapsed)
        withExtendedLifetime(source.sidebar) {}
    }
}

extension FileSwitchOutcome {
    var isSwitched: Bool {
        if case .switched = self { return true }
        return false
    }
}
