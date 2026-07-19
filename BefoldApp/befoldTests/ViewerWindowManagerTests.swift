import AppKit
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct ViewerWindowManagerTests {
    private func makeManager(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
    ) -> ViewerWindowManager {
        ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            hiddenFilesPreference: HiddenFilesPreference(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults)
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
            sessionStore: sessionStore,
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults)
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

    @Test("ファイルを開くと Open Recent 履歴に記録される")
    func openViewerRecordsRecentDocument() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let recentStore = RecentDocumentsStore(defaults: defaults)
        let manager = makeManager(defaults: defaults)

        manager.openViewer(for: file)

        #expect(recentStore.recentURLs().map(\.path) == [file.normalizedPathKey])
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("rename が Open Recent 履歴に反映される")
    func renameUpdatesRecentDocuments() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "old.mmd", contents: "graph TD;")
        let renamed = try tmp.file(named: "new.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let recentStore = RecentDocumentsStore(defaults: defaults)
        let manager = makeManager(defaults: defaults)
        manager.openViewer(for: file)

        let controller = try #require(manager.controllers[file.normalizedPathKey])
        manager.viewerWindow(controller, didRenameFrom: file, to: renamed)

        #expect(recentStore.recentURLs().map(\.path) == [renamed.normalizedPathKey])
        manager.controllers.values.forEach { $0.close() }
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

    @Test("toggleHiddenFiles は状態を反転し開いているサイドバーへ反映する")
    func toggleHiddenFilesRefreshesOpenSidebar() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let manager = makeManager()

        manager.openViewer(for: visible)
        let controller = try #require(manager.controllers[visible.normalizedPathKey])
        #expect(!controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))

        manager.toggleHiddenFiles()
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("toggleHiddenFiles は複数の開いているウィンドウすべてへ同時に反映する")
    func toggleHiddenFilesAffectsAllOpenWindows() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)

        manager.toggleHiddenFiles()
        for controller in manager.controllers.values {
            await controller.sidebar.pendingListingTask?.value
        }

        for controller in manager.controllers.values {
            #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("ウィンドウのアイコンボタン操作(onToggleHiddenFiles)でも全ウィンドウが同期する")
    func onToggleHiddenFilesCallbackTogglesAllWindows() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)
        let first = try #require(manager.controllers[file1.normalizedPathKey])

        manager.viewerWindowDidToggleHiddenFiles(first)
        for controller in manager.controllers.values {
            await controller.sidebar.pendingListingTask?.value
        }

        for controller in manager.controllers.values {
            #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("switchFile で管理辞書のキーが付け替わりセッション記録が更新される")
    func switchFileUpdatesControllerKeyAndSession() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let sessionStore = SessionStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults)
        )

        manager.openViewer(for: file1)
        #expect(manager.controllers[file1.normalizedPathKey] != nil)

        let controller = try #require(manager.controllers[file1.normalizedPathKey])
        manager.viewerWindow(controller, didSwitchFileFrom: file1, to: file2)

        #expect(manager.controllers[file1.normalizedPathKey] == nil)
        #expect(manager.controllers[file2.normalizedPathKey] != nil)
        let savedPaths = sessionStore.savedURLs().map(\.normalizedPathKey)
        #expect(savedPaths.contains(file2.normalizedPathKey))
        #expect(!savedPaths.contains(file1.normalizedPathKey))
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("新規ファイルを開くと、記録がなければ既定(閉じた状態)がサイドバー状態として記録される")
    func openViewerPersistsDefaultClosedSidebarStateForNewFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: perFileState
        )

        manager.openViewer(for: file)

        #expect(perFileState.sidebar.isCollapsed(for: file) == true)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("既に保存済みのサイドバー状態があるファイルを開いても保存値は上書きされない")
    func openViewerKeepsOwnSavedSidebarState() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        perFileState.sidebar.setCollapsed(false, for: file)
        let manager = ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: perFileState
        )

        manager.openViewer(for: file)

        #expect(perFileState.sidebar.isCollapsed(for: file) == false)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("初めて開くファイルは直近アクティブだったウィンドウのサイドバー状態を引き継ぐ")
    func openViewerInheritsLastActiveWindowSidebarState() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let activeFile = try tmp.file(named: "active.mmd", contents: "graph TD;")
        let newFile = try tmp.file(named: "new.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let sessionStore = SessionStore(defaults: defaults)
        let perFileState = PerFileStateStore(defaults: defaults)
        perFileState.sidebar.setCollapsed(false, for: activeFile)
        sessionStore.noteActivated(activeFile)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: perFileState
        )

        manager.openViewer(for: newFile)

        #expect(perFileState.sidebar.isCollapsed(for: newFile) == false)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("forceSidebarVisible は保存済み・引き継ぎ値より優先され、結果も記録される")
    func openViewerForceSidebarVisibleOverridesResolvedDefault() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: perFileState
        )

        manager.openViewer(for: file, forceSidebarVisible: true)

        #expect(perFileState.sidebar.isCollapsed(for: file) == false)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("既に保存済みのウィンドウフレームがあるファイルを開いても保存値は上書きされない")
    func openViewerKeepsOwnSavedWindowFrame() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        perFileState.windowFrame.setFrameDescriptor("200 200 900 700 0 0 1920 1080", for: file)
        let manager = ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: perFileState
        )

        manager.openViewer(for: file)

        #expect(perFileState.windowFrame.frameDescriptor(for: file) == "200 200 900 700 0 0 1920 1080")
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("初めて開くファイルは直近アクティブだったウィンドウのフレームを引き継ぐ")
    func openViewerInheritsLastActiveWindowFrame() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let activeFile = try tmp.file(named: "active.mmd", contents: "graph TD;")
        let newFile = try tmp.file(named: "new.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let sessionStore = SessionStore(defaults: defaults)
        let perFileState = PerFileStateStore(defaults: defaults)
        perFileState.windowFrame.setFrameDescriptor("50 50 700 500 0 0 1920 1080", for: activeFile)
        sessionStore.noteActivated(activeFile)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: perFileState
        )

        manager.openViewer(for: newFile)

        #expect(perFileState.windowFrame.frameDescriptor(for: newFile) == "50 50 700 500 0 0 1920 1080")
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("記録が何もない新規ファイルはウィンドウフレームを記録しない(既定のカスケード配置に任せる)")
    func openViewerLeavesWindowFrameUnsetWhenNothingToInherit() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            perFileState: perFileState
        )

        manager.openViewer(for: file)

        #expect(perFileState.windowFrame.frameDescriptor(for: file) == nil)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("別ウィンドウで開いているファイルへの切替は中止され重複ウィンドウを作らない")
    func switchToFileOpenInAnotherWindowIsRejected() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)
        let first = try #require(manager.controllers[file1.normalizedPathKey])

        // file2 は別ウィンドウで開いているため、切替は中止され file1 のまま残る。
        first.switchFile(to: file2)

        #expect(manager.controllers.count == 2)
        #expect(manager.controllers[file1.normalizedPathKey] === first)
        #expect(first.fileURL == file1)
        manager.controllers.values.forEach { $0.close() }
    }
}
