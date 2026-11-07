import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// 空タブを文書タブへ置き換えるとき、何がどう引き継がれるか(TASK-910 / 914 / 918 / 919)。
/// `BlankTabSidebarTests` から行数の上限のため分けた。補助は同じものを持つ。
@Suite
@MainActor
struct BlankTabReplacementTests {
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

    /// 文書タブはサイドバーの行を選んでも表示中のフォルダを動かさない(TASK-465)。空タブを挟んで
    /// ツリーのルートが選んだファイルの親へ移り、展開が消えるとこの規則が空タブだけ破れる。
    @Test("空タブのツリーで子のファイルを選ぶと、置き換えた文書タブのルートと展開が保たれる", testTimeLimit())
    func replacingFromTreeKeepsRootAndExpansion() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let inner = try tmp.file(atPath: "sub/inner.md", contents: "fixture")
        let folder = inner.deletingLastPathComponent()
        let fixture = MockedViewerWindowManager(files: [origin, inner], directories: [folder])
        defer { fixture.closeAll() }
        fixture.displayDefaults.record { $0.layoutMode = .tree }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let navigator = try #require(blank.inheritableSidebar)
        await navigator.awaitSettled()
        navigator.expandFolder(folder.normalizedPathKey, at: folder)
        await navigator.awaitSettled()
        let root = navigator.fileListModel.currentDirectory.normalizedPathKey

        #expect(blank.performFileSwitch(to: inner).isSwitched)

        let replaced = try #require(fixture.manager.controllers[inner.normalizedPathKey]?.first)
        await replaced.sidebar.awaitSettled()
        #expect(replaced.fileListModel.currentDirectory.normalizedPathKey == root)
        #expect(replaced.fileListModel.rootDirectory.normalizedPathKey == root)
        #expect(replaced.sidebar.expandedFolderURLs[folder.normalizedPathKey] != nil)
        #expect(replaced.fileListModel.selection?.normalizedPathKey == inner.normalizedPathKey)
    }

    /// 引き継ぐのは、文書タブでもフォルダを動かさない場合だけ。閉じたフォルダの中や一覧の外の
    /// ファイルは今の一覧から選べないので、文書タブと同じくファイルの親から始める。
    @Test("空タブの一覧から選べないファイルは、置き換えた文書タブがファイルの親から始まる", testTimeLimit(), arguments: [false, true])
    func unreachableFileStartsAtItsParent(outsideFolder: Bool) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let inner = try tmp.file(atPath: "sub/inner.md", contents: "fixture")
        let elsewhere = try TempDir()
        defer { withExtendedLifetime(elsewhere) {} }
        let outside = try elsewhere.file(named: "outside.md", contents: "fixture")
        let target = outsideFolder ? outside : inner
        let fixture = MockedViewerWindowManager(
            files: [origin, inner, outside], directories: [inner.deletingLastPathComponent()]
        )
        defer { fixture.closeAll() }
        fixture.displayDefaults.record { $0.layoutMode = .tree }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        await blank.inheritableSidebar?.awaitSettled()

        #expect(blank.performFileSwitch(to: target).isSwitched)

        let replaced = try #require(fixture.manager.controllers[target.normalizedPathKey]?.first)
        #expect(
            replaced.fileListModel.currentDirectory.normalizedPathKey
                == target.deletingLastPathComponent().normalizedPathKey
        )
    }

    /// 空タブで変えた比較基準を、置き換えで既定値へ戻さない(TASK-919)。
    @Test("空タブで変えた比較基準は、置き換えた文書タブへ引き継がれる")
    func replacedDocumentKeepsComparisonTarget() throws {
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        let source = try makeSource(in: fixture, collapsed: false)
        let blank = fixture.manager.blankTabs.open(relativeTo: source.window)
        defer { blank.close() }
        let changed = try #require(GitComparisonTarget.allCases.first { $0 != .windowDefault })
        blank.fileListDidRequestComparisonTarget(changed)

        #expect(blank.performFileSwitch(to: second).isSwitched)

        let replaced = try #require(fixture.manager.controllers[second.normalizedPathKey]?.first)
        #expect(replaced.comparisonTarget == changed)
        withExtendedLifetime(source.sidebar) {}
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

        let seed = SidebarInheritance.seed(from: blank.window, opensAsTab: true, replacing: nil, opening: nil)

        #expect(seed.expansion[folder.normalizedPathKey] == folder)
        withExtendedLifetime(source.sidebar) {}
    }
}
