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
        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
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

    /// navigateToFolder はホームディレクトリ配下のみ許可するため、システム一時ディレクトリではなく
    /// ホームディレクトリ配下に一時ディレクトリを作る。
    private func makeHomeTempDir() throws -> TempDir {
        try TempDir(base: FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test("navigateToFolder でカレントディレクトリと一覧が更新される")
    func navigateToFolderUpdatesCurrentDirectoryAndEntries() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.navigateToFolder(subDir)

        #expect(controller.fileListModel.currentDirectory.standardizedFileURL == subDir.standardizedFileURL)
        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains("child.mmd"))
    }

    @Test("navigateToFolder で親フォルダーへ移動できる")
    func navigateToFolderToParentWorks() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let file = try tmp.file(named: "sub/child.mmd", contents: "graph TD;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.navigateToFolder(tmp.url)

        #expect(controller.fileListModel.currentDirectory.standardizedFileURL == tmp.url.standardizedFileURL)
    }

    @Test("navigateToFolder はホームディレクトリより上には移動しない")
    func navigateToFolderRefusesAboveHomeDirectory() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }
        let before = controller.fileListModel.currentDirectory
        let aboveHome = FileManager.default.homeDirectoryForCurrentUser
            .deletingLastPathComponent()

        controller.navigateToFolder(aboveHome)

        #expect(controller.fileListModel.currentDirectory == before)
    }

    @Test("子フォルダーへの移動ではフォルダーをスキップして最初のファイルが選択される")
    func navigateToChildSelectsFirstFileSkippingFolders() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        // フォルダーファースト順ではフォルダーがファイルより先頭に来るため、
        // 「先頭エントリ」選択だと grandchild が選ばれてしまう配置にする。
        let grandChild = subDir.appendingPathComponent("grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: grandChild, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.navigateToFolder(subDir)

        #expect(controller.fileListModel.selection?.lastPathComponent == "child.mmd")
    }

    @Test("子フォルダーへの移動では最初のファイルが表示対象として開かれる")
    func navigateToChildOpensFirstFile() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.navigateToFolder(subDir)

        #expect(controller.fileURL.lastPathComponent == "child.mmd")
    }

    @Test("ファイルのない子フォルダーへの移動では何も選択されない")
    func navigateToChildWithoutFilesClearsSelection() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let grandChild = subDir.appendingPathComponent("grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: grandChild, withIntermediateDirectories: true)
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.navigateToFolder(subDir)

        #expect(controller.fileListModel.selection == nil)
    }

    @Test("親フォルダーへの移動では直前の子フォルダーが選択される")
    func navigateToParentSelectsPreviousChild() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let file = try tmp.file(named: "sub/child.mmd", contents: "graph TD;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.navigateToFolder(tmp.url)

        #expect(controller.fileListModel.selection?.lastPathComponent == "sub")
    }
}
