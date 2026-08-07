import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// タブ結合は実 NSWindow の tabGroup を使うため、MockedViewerWindowManager 経由で
/// 実ウィンドウを生成して検証する(store と directoryLister はモック済み)。
@Suite
@MainActor
struct ViewerWindowManagerTabTests {
    @Test("newTab で開くと起点ウィンドウのタブグループに入り選択タブになる")
    func newTabJoinsSourceTabGroup() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newTab, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup != nil)
        #expect(secondWindow?.tabGroup === firstWindow?.tabGroup)
        #expect(secondWindow?.tabGroup?.selectedWindow === secondWindow)
        fixture.closeAll()
    }

    @Test("起点ウィンドウが無ければ独立したウィンドウとして開く")
    func newTabWithoutSourceFallsBackToWindow() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: file, disposition: .newTab, relativeTo: nil)

        #expect(fixture.manager.window(forPath: file.normalizedPathKey) != nil)
        fixture.closeAll()
    }

    @Test("newWindow は起点ウィンドウを渡してもタブ結合しない")
    func newWindowNeverJoinsTabGroup() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newWindow, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup?.windows.contains(where: { $0 === firstWindow }) != true)
        fixture.closeAll()
    }

    @Test("既に開いているファイルでも newWindow なら新しいウィンドウを開く")
    func newWindowOpensDuplicateForAlreadyOpenFile() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: file)
        let firstWindow = fixture.manager.window(forPath: file.normalizedPathKey)
        fixture.manager.openViewer(for: file, disposition: .newWindow, relativeTo: firstWindow)

        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 2)
        fixture.closeAll()
    }

    @Test("既に開いているファイルでも newTab なら起点のタブグループへ新しいタブを開く")
    func newTabOpensDuplicateForAlreadyOpenFile() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: file)
        let firstWindow = fixture.manager.window(forPath: file.normalizedPathKey)
        fixture.manager.openViewer(for: file, disposition: .newTab, relativeTo: firstWindow)

        let opened = fixture.manager.controllers[file.normalizedPathKey] ?? []
        #expect(opened.count == 2)
        #expect(opened.last?.window?.tabGroup === firstWindow?.tabGroup)
        fixture.closeAll()
    }

    @Test("Finder/CLI 由来の再オープン(currentTab)は重複ウィンドウを作らない")
    func currentTabReopenReusesExistingWindow() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: file)

        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 1)
        fixture.closeAll()
    }
}
