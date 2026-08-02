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
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newTab, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup != nil)
        #expect(secondWindow?.tabGroup === firstWindow?.tabGroup)
        #expect(secondWindow?.tabGroup?.selectedWindow === secondWindow)
    }

    @Test("起点ウィンドウが無ければ独立したウィンドウとして開く")
    func newTabWithoutSourceFallsBackToWindow() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file, disposition: .newTab, relativeTo: nil)

        #expect(fixture.manager.window(forPath: file.normalizedPathKey) != nil)
    }

    @Test("newWindow は起点ウィンドウを渡してもタブ結合しない")
    func newWindowNeverJoinsTabGroup() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newWindow, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup?.windows.contains(where: { $0 === firstWindow }) != true)
    }
}
