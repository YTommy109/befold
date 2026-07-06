import AppKit
@testable import befold
import Foundation
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
        first.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

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

    @Test("switchFile は旧・新ファイルの保存済み倍率を破壊しない")
    func switchFilePreservesSavedZoomForBothFiles() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let zoomStore = ZoomStore(defaults: defaults)
        zoomStore.setZoom(2.0, for: file1)
        zoomStore.setZoom(0.75, for: file2)
        let controller = ViewerWindowController(fileURL: file1, zoomStore: zoomStore, defaults: defaults)
        defer { controller.close() }

        controller.switchFile(to: file2)

        // 切替はリネームではないため、双方の保存倍率が独立して保たれる。
        #expect(zoomStore.zoom(for: file1) == 2.0)
        #expect(zoomStore.zoom(for: file2) == 0.75)
    }

    @Test("rename でサイドバーの一覧が再取得され新名が選択される")
    func renameRefreshesSidebarListAndSelection() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "old.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults
        )
        defer { controller.close() }
        let renamed = tmp.url.appendingPathComponent("new.mmd")
        try FileManager.default.moveItem(at: file, to: renamed)

        controller.handleRename(to: renamed)

        // ディレクトリ列挙は /private シンボリックリンクを解決するため、名前で照合する。
        let names = controller.fileListModel.files.map(\.lastPathComponent)
        #expect(controller.fileListModel.selection?.lastPathComponent == "new.mmd")
        #expect(names.contains("new.mmd"))
        #expect(!names.contains("old.mmd"))
    }

    @Test("対応形式への rename ではソース表示が維持される")
    func renameToRenderableKeepsSourceMode() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults
        )
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = tmp.url.appendingPathComponent("note.markdown")
        try FileManager.default.moveItem(at: file, to: renamed)

        controller.handleRename(to: renamed)

        #expect(controller.isSourceMode)
    }

    @Test("非対応形式への rename ではソース表示が解除される")
    func renameToNonRenderableResetsSourceMode() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults
        )
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = tmp.url.appendingPathComponent("note.swift")
        try FileManager.default.moveItem(at: file, to: renamed)

        controller.handleRename(to: renamed)

        // .swift は isRenderable == false のため、ソース表示トグルが成立せずリセットする。
        #expect(!controller.isSourceMode)
    }
}
