import AppKit
import Foundation
@testable import mmdview
import Testing

@Suite
@MainActor
struct ViewerWindowControllerTests {
    @Test("ファイル別の frameAutosaveName は設定されない")
    func noPerFileFrameAutosave() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")

        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(
                defaults: makeIsolatedDefaults(
                    prefix: "ViewerWindowControllerTests"
                )
            )
        )
        defer { controller.close() }

        #expect(controller.windowFrameAutosaveName == "")
    }

    @Test("保存されたフレームがなければデフォルトのコンテンツサイズで開く")
    func windowOpensAtDefaultSizeWithoutSavedFrame() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")

        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults
        )
        defer { controller.close() }

        let contentSize = controller.window.map {
            $0.contentRect(forFrameRect: $0.frame).size
        } ?? .zero
        #expect(contentSize == NSSize(width: 1100, height: 850))
    }

    @Test("ウィンドウフレーム(位置とサイズ)が次のウィンドウに引き継がれる")
    func windowFrameIsPersistedAcrossControllers() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let zoomStore = ZoomStore(defaults: defaults)

        let first = ViewerWindowController(fileURL: file, zoomStore: zoomStore, defaults: defaults)
        defer { first.close() }
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        first.window?.setFrame(frame, display: false)
        first.windowDidResize(Notification(name: NSWindow.didResizeNotification))

        let second = ViewerWindowController(fileURL: file, zoomStore: zoomStore, defaults: defaults)
        defer { second.close() }

        #expect(second.window?.frame == frame)
    }

    @Test("ウィンドウを閉じたときにもフレームが保存される")
    func windowFrameIsSavedOnClose() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let zoomStore = ZoomStore(defaults: defaults)

        let first = ViewerWindowController(fileURL: file, zoomStore: zoomStore, defaults: defaults)
        let frame = NSRect(x: 160, y: 180, width: 800, height: 650)
        first.window?.setFrame(frame, display: false)
        first.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        first.close()

        let second = ViewerWindowController(fileURL: file, zoomStore: zoomStore, defaults: defaults)
        defer { second.close() }

        #expect(second.window?.frame == frame)
    }

    @Test("windowDidBecomeKey で onBecomeKey コールバックが呼ばれる")
    func windowDidBecomeKeyInvokesCallback() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }
        var becameKey = false
        controller.onBecomeKey = { becameKey = true }

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        #expect(becameKey)
    }

    @Test("switchFile でファイル URL とウィンドウタイトルが更新される")
    func switchFileUpdatesFileURLAndTitle() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
        let controller = ViewerWindowController(
            fileURL: file1,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.switchFile(to: file2)

        #expect(controller.fileURL == file2)
        #expect(controller.window?.title == "second.mmd")
        #expect(controller.window?.representedURL == file2)
    }

    @Test("switchFile で onSwitchFile コールバックが旧・新 URL で呼ばれる")
    func switchFileInvokesCallback() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
        let controller = ViewerWindowController(
            fileURL: file1,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }
        var callbackArgs: (old: URL, new: URL)?
        controller.onSwitchFile = { old, new in callbackArgs = (old, new) }

        controller.switchFile(to: file2)

        #expect(callbackArgs?.old == file1)
        #expect(callbackArgs?.new == file2)
    }

    @Test("switchFile で同じファイルを選んでも何も起きない")
    func switchFileIgnoresSameFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }
        var called = false
        controller.onSwitchFile = { _, _ in called = true }

        controller.switchFile(to: file)

        #expect(!called)
    }
}
