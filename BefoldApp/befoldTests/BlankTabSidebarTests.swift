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

    @Test("サイドバーでファイルを選ぶと空タブが同じ位置で文書タブに置き換わる")
    func selectingFileReplacesBlankInPlace() throws {
        let last = URL(fileURLWithPath: "/mock/folder/last.md")
        let fixture = MockedViewerWindowManager(files: [first, second, last])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }
        let blankWindow = try #require(blank.window)
        let trailing = try #require(fixture.manager.openViewer(
            for: last, disposition: .newTab, relativeTo: blankWindow
        )?.window)

        #expect(blank.performFileSwitch(to: second).isSwitched)

        let replaced = try #require(fixture.manager.controllers[second.normalizedPathKey]?.first?.window)
        #expect(source.window.tabGroup?.windows == [source.window, replaced, trailing])
        #expect(source.window.tabGroup?.selectedWindow === replaced)
        #expect(blank.isClosed)
        withExtendedLifetime(source.sidebar) {}
    }

    /// 置き換えた窓の表は空タブの表と別物なので、フォーカスを渡し直さないとキー操作が続かない。
    @Test("サイドバーから置き換えた文書タブでは、サイドバーの表がフォーカスを受ける")
    func replacedDocumentSidebarTakesFocus() throws {
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }

        #expect(blank.performFileSwitch(to: second).isSwitched)

        let replaced = try #require(fixture.manager.controllers[second.normalizedPathKey]?.first)
        #expect(replaced.fileListModel.tableFocuser.focusPending)
        withExtendedLifetime(source.sidebar) {}
    }

    /// 同じグループで開いている既存のタブを再利用するとき、そのタブのサイドバーが閉じていれば
    /// フォーカスを移さない。見えない一覧が矢印キーを受けて、黙ってファイルが切り替わるため。
    @Test("再利用した既存のタブのサイドバーが閉じていれば、表へフォーカスを移さない")
    func reusedTabWithCollapsedSidebarKeepsFocus() throws {
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)
        let existing = try #require(fixture.manager.openViewer(
            for: second, disposition: .newTab, relativeTo: source.window
        ))
        let existingSidebar = RecordingSidebarCollapsible()
        existingSidebar.resolvedSidebarCollapsed = true
        existing.sidebarCollapsible = existingSidebar
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }

        #expect(blank.performFileSwitch(to: second).isSwitched)

        #expect(blank.isClosed)
        #expect(!existing.fileListModel.tableFocuser.focusPending)
        withExtendedLifetime((source.sidebar, existingSidebar)) {}
    }

    @Test("存在しないファイルを選んでも空タブは残る")
    func missingFileKeepsBlank() throws {
        let fixture = MockedViewerWindowManager(files: [first])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }

        #expect(!blank.performFileSwitch(to: second).isSwitched)

        #expect(!blank.isClosed)
        withExtendedLifetime(source.sidebar) {}
    }

    @Test("置き換えた文書タブは空タブのサイドバーの開閉を引き継ぐ", arguments: [true, false])
    func replacedDocumentKeepsCollapse(collapsed: Bool) throws {
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: collapsed)
        fixture.sidebarState.recordToggle(!collapsed)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }

        _ = blank.performFileSwitch(to: second)

        let replaced = try #require(fixture.manager.controllers[second.normalizedPathKey]?.first)
        #expect(replaced.initialSidebarCollapsed == collapsed)
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

    /// 文書タブと同じく、移動先の先頭がファイルならそれを開く(TASK-310)。空タブでは置き換えになる。
    @Test("サイドバーのフォルダ移動で先頭がファイルなら空タブが文書へ置き換わる", testTimeLimit())
    func navigatingToFolderWithFileReplacesBlank() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let inner = try tmp.file(atPath: "sub/inner.md", contents: "fixture")
        // 実際の一覧は実パス(/private/var/...)を返すが、resolvingSymlinksInPath は /var へ戻すので
        // 明示して載せる。モックに無いパスは切替の失敗になる。
        let listed = URL(fileURLWithPath: "/private" + inner.path)
        let files = [origin, inner, listed]
        let fixture = MockedViewerWindowManager(files: files, directories: [inner.deletingLastPathComponent()])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let navigator = try #require(blank.inheritableSidebar)

        blank.fileListDidRequestNavigation(to: inner.deletingLastPathComponent())
        await navigator.awaitSettled()

        #expect(blank.isClosed)
        #expect(fixture.manager.allControllers.contains { $0.fileURL.lastPathComponent == "inner.md" })
    }

    /// 展開と一覧の採取が文書タブに限られていると、空タブを挟んだだけで失われる。
    @Test("空タブからの引き継ぎの束に一覧と展開が入る")
    func seedReadsBlankTabSidebar() throws {
        let fixture = MockedViewerWindowManager(files: [first])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }
        let navigator = try #require(blank.inheritableSidebar)
        let folder = first.deletingLastPathComponent().appendingPathComponent("sub", isDirectory: true)
        navigator.expandFolder(folder.normalizedPathKey, at: folder)

        let seed = SidebarInheritance.seed(from: blank.window, opensAsTab: true)

        #expect(seed.expansion[folder.normalizedPathKey] == folder)
        withExtendedLifetime(source.sidebar) {}
    }
}

private extension FileSwitchOutcome {
    var isSwitched: Bool {
        if case .switched = self { return true }
        return false
    }
}
