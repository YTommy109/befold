import AppKit
import Foundation
@testable import mmdview
import Testing

@Suite
@MainActor
struct ViewerWindowManagerTests {
    private func makeManager() -> ViewerWindowManager {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        return ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            zoomStore: ZoomStore(defaults: defaults)
        )
    }

    @Test("同じファイルを二度開いてもウィンドウは 1 つに集約される")
    func openViewerReusesControllerForSamePath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let manager = makeManager()

        manager.openViewer(for: file)
        manager.openViewer(for: file)

        #expect(manager.controllers.count == 1)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("ウィンドウクローズで管理辞書から除去されセッション記録も閉じられる")
    func closingWindowRemovesControllerAndNotesClosed() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let sessionStore = SessionStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore, zoomStore: ZoomStore(defaults: defaults)
        )

        manager.openViewer(for: file)
        #expect(sessionStore.savedURLs().map(\.normalizedPathKey) == [file.normalizedPathKey])

        manager.controllers[file.normalizedPathKey]?.close()

        #expect(manager.controllers.isEmpty)
        #expect(sessionStore.savedURLs().isEmpty)
    }

    @Test("可視なのにアクティブ Space に居ないウィンドウだけが救出対象と判定される")
    func isDetachedFromSpaceRequiresVisibleAndOffActiveSpace() {
        #expect(ViewerWindowManager.isDetachedFromSpace(isVisible: true, isOnActiveSpace: false))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: true, isOnActiveSpace: true))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: false, isOnActiveSpace: false))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: false, isOnActiveSpace: true))
    }

    @Test("window(forPath:) が開いたウィンドウを返す")
    func windowForPathReturnsOpenWindow() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let manager = makeManager()

        manager.openViewer(for: file)

        let window = manager.window(forPath: file.normalizedPathKey)
        #expect(window != nil)
        let unwrappedWindow = try #require(window)
        #expect(manager.viewerPath(of: unwrappedWindow) == file.normalizedPathKey)
        manager.controllers.values.forEach { $0.close() }
    }
}
