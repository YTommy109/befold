import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ViewerWindowManager の辞書管理・セッション記録・サイドバー開閉/フレームの初期状態解決を検証する。
/// コントローラ生成は MockedViewerWindowManager 経由で InMemoryFileReader + MockFileWatcher +
/// 空のディレクトリ列挙に差し替えているため実 FS を踏まない。
/// サイドバー entries の実列挙が対象のテストは ViewerWindowManagerIntegrationTests に残している。
@Suite
@MainActor
struct ViewerWindowManagerTests {
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")
    private let file1 = URL(fileURLWithPath: "/mock/first.mmd")
    private let file2 = URL(fileURLWithPath: "/mock/second.mmd")

    @Test("可視なのにアクティブ Space に居ないウィンドウだけが救出対象と判定される")
    func isDetachedFromSpaceRequiresVisibleAndOffActiveSpace() {
        #expect(ViewerWindowManager.isDetachedFromSpace(isVisible: true, isOnActiveSpace: false))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: true, isOnActiveSpace: true))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: false, isOnActiveSpace: false))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: false, isOnActiveSpace: true))
    }

    @Test("同じファイルを二度開いてもウィンドウは 1 つに集約される")
    func openViewerReusesControllerForSamePath() {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: file)

        #expect(fixture.manager.controllers.count == 1)
        fixture.closeAll()
    }

    @Test("単一ファイル指定では従来通りウィンドウは1つだけ開く(回帰確認)")
    func singleCLITargetOpensExactlyOneWindow() {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file)

        #expect(fixture.manager.controllers.count == 1)
        fixture.closeAll()
    }

    @Test("ウィンドウクローズで管理辞書から除去されセッション記録も閉じられる")
    func closingWindowRemovesControllerAndNotesClosed() {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file)
        #expect(fixture.sessionStore.savedURLs().map(\.normalizedPathKey) == [file.normalizedPathKey])

        fixture.manager.controllers[file.normalizedPathKey]?.close()

        #expect(fixture.manager.controllers.isEmpty)
        #expect(fixture.sessionStore.savedURLs().isEmpty)
    }

    @Test("ファイルを開くと Open Recent 履歴に記録される")
    func openViewerRecordsRecentDocument() {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file)

        #expect(fixture.recentDocumentsStore.recentURLs().map(\.path) == [file.normalizedPathKey])
        fixture.closeAll()
    }

    @Test("rename が Open Recent 履歴に反映される")
    func renameUpdatesRecentDocuments() throws {
        let old = URL(fileURLWithPath: "/mock/old.mmd")
        let renamed = URL(fileURLWithPath: "/mock/new.mmd")
        let fixture = MockedViewerWindowManager(files: [old, renamed])
        fixture.manager.openViewer(for: old)

        let controller = try #require(fixture.manager.controllers[old.normalizedPathKey])
        fixture.manager.viewerWindow(controller, didRenameFrom: old, to: renamed)

        #expect(fixture.recentDocumentsStore.recentURLs().map(\.path) == [renamed.normalizedPathKey])
        fixture.closeAll()
    }

    @Test("window(forPath:) が開いたウィンドウを返す")
    func windowForPathReturnsOpenWindow() throws {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file)

        let window = try #require(fixture.manager.window(forPath: file.normalizedPathKey))
        #expect(fixture.manager.viewerPath(of: window) == file.normalizedPathKey)
        fixture.closeAll()
    }

    @Test("switchFile で管理辞書のキーが付け替わりセッション記録が更新される")
    func switchFileUpdatesControllerKeyAndSession() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])

        fixture.manager.openViewer(for: file1)
        let controller = try #require(fixture.manager.controllers[file1.normalizedPathKey])
        fixture.manager.viewerWindow(controller, didSwitchFileFrom: file1, to: file2)

        #expect(fixture.manager.controllers[file1.normalizedPathKey] == nil)
        #expect(fixture.manager.controllers[file2.normalizedPathKey] != nil)
        let savedPaths = fixture.sessionStore.savedURLs().map(\.normalizedPathKey)
        #expect(savedPaths.contains(file2.normalizedPathKey))
        #expect(!savedPaths.contains(file1.normalizedPathKey))
        fixture.closeAll()
    }

    @Test("別ウィンドウで開いているファイルへの切替は中止され重複ウィンドウを作らない")
    func switchToFileOpenInAnotherWindowIsRejected() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        fixture.manager.openViewer(for: file1)
        fixture.manager.openViewer(for: file2)
        let first = try #require(fixture.manager.controllers[file1.normalizedPathKey])

        // file2 は別ウィンドウで開いているため、切替は中止され file1 のまま残る。
        first.switchFile(to: file2)

        #expect(fixture.manager.controllers.count == 2)
        #expect(fixture.manager.controllers[file1.normalizedPathKey] === first)
        #expect(first.fileURL == file1)
        fixture.closeAll()
    }

    @Test("新規ファイルを開くと、記録がなければ既定(閉じた状態)がサイドバー状態として記録される")
    func openViewerPersistsDefaultClosedSidebarStateForNewFile() {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == true)
        fixture.closeAll()
    }

    @Test("既に保存済みのサイドバー状態があるファイルを開いても保存値は上書きされない")
    func openViewerKeepsOwnSavedSidebarState() {
        let fixture = MockedViewerWindowManager(files: [file])
        fixture.perFileState.sidebar.setCollapsed(false, for: file)

        fixture.manager.openViewer(for: file)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
        fixture.closeAll()
    }

    @Test("初めて開くファイルは直近アクティブだったウィンドウのサイドバー状態を引き継ぐ")
    func openViewerInheritsLastActiveWindowSidebarState() {
        let activeFile = URL(fileURLWithPath: "/mock/active.mmd")
        let newFile = URL(fileURLWithPath: "/mock/new.mmd")
        let fixture = MockedViewerWindowManager(files: [activeFile, newFile])
        fixture.perFileState.sidebar.setCollapsed(false, for: activeFile)
        fixture.sessionStore.noteActivated(activeFile)

        fixture.manager.openViewer(for: newFile)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: newFile) == false)
        fixture.closeAll()
    }

    @Test("forceSidebarVisible は保存済み・引き継ぎ値より優先され、結果も記録される")
    func openViewerForceSidebarVisibleOverridesResolvedDefault() {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file, forceSidebarVisible: true)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
        fixture.closeAll()
    }

    @Test("既に保存済みのウィンドウフレームがあるファイルを開いても保存値は上書きされない")
    func openViewerKeepsOwnSavedWindowFrame() {
        let fixture = MockedViewerWindowManager(files: [file])
        fixture.perFileState.windowFrame.setFrameDescriptor("200 200 900 700 0 0 1920 1080", for: file)

        fixture.manager.openViewer(for: file)

        #expect(
            fixture.perFileState.windowFrame.frameDescriptor(for: file) == "200 200 900 700 0 0 1920 1080"
        )
        fixture.closeAll()
    }

    @Test("初めて開くファイルは直近アクティブだったウィンドウのフレームを引き継ぐ")
    func openViewerInheritsLastActiveWindowFrame() {
        let activeFile = URL(fileURLWithPath: "/mock/active.mmd")
        let newFile = URL(fileURLWithPath: "/mock/new.mmd")
        let fixture = MockedViewerWindowManager(files: [activeFile, newFile])
        fixture.perFileState.windowFrame.setFrameDescriptor("50 50 700 500 0 0 1920 1080", for: activeFile)
        fixture.sessionStore.noteActivated(activeFile)

        fixture.manager.openViewer(for: newFile)

        #expect(
            fixture.perFileState.windowFrame.frameDescriptor(for: newFile) == "50 50 700 500 0 0 1920 1080"
        )
        fixture.closeAll()
    }

    @Test("記録が何もない新規ファイルはウィンドウフレームを記録しない(既定のカスケード配置に任せる)")
    func openViewerLeavesWindowFrameUnsetWhenNothingToInherit() {
        let fixture = MockedViewerWindowManager(files: [file])

        fixture.manager.openViewer(for: file)

        #expect(fixture.perFileState.windowFrame.frameDescriptor(for: file) == nil)
        fixture.closeAll()
    }
}
