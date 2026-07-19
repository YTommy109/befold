import AppKit
@testable import befold
import Foundation
import Testing

private final class MockViewerWindowControllerDelegate: ViewerWindowControllerDelegate {
    var becomeKeyCalled = false
    var closeCalled = false
    var renameArgs: (old: URL, new: URL)?
    var switchFileArgs: (old: URL, new: URL)?
    var toggleHiddenFilesCalled = false
    private let isFileOpenCheck: (URL) -> Bool

    init(isFileOpenCheck: @escaping (URL) -> Bool = { _ in false }) {
        self.isFileOpenCheck = isFileOpenCheck
    }

    func viewerWindowWillClose(_ controller: ViewerWindowController) {
        closeCalled = true
    }

    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController) {
        becomeKeyCalled = true
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL
    ) {
        renameArgs = (oldURL, newURL)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    ) {
        switchFileArgs = (oldURL, newURL)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, isFileOpenInAnotherWindow url: URL
    ) -> Bool {
        isFileOpenCheck(url)
    }

    func viewerWindow(_ controller: ViewerWindowController, focusWindowForFile url: URL) {}

    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController) {
        toggleHiddenFilesCalled = true
    }
}

@Suite
@MainActor
struct ViewerWindowControllerTests {
    /// テスト用に隔離済み UserDefaults(既定は使い捨て)と ZoomStore / SourceModeStore を注入したコントローラーを作る。
    /// 呼び出し側で defaults / zoomStore / sourceModeStore を後から参照したい場合は明示的に渡す。
    private func makeController(
        file: URL,
        zoomStore: ZoomStore? = nil,
        sourceModeStore: SourceModeStore? = nil,
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
    ) -> ViewerWindowController {
        ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            perFileState: PerFileStateStore(
                zoom: zoomStore ?? ZoomStore(defaults: defaults),
                sourceMode: sourceModeStore ?? SourceModeStore(defaults: defaults),
                scrollPosition: ScrollPositionStore(defaults: defaults)
            ),
            bookmarkStore: BookmarkStore(defaults: defaults)
        )
    }

    @Test("hiddenFilesPreference.showHiddenFiles が true のときサイドバーに不可視ファイルが含まれる")
    func sidebarIncludesHiddenFilesWhenPreferenceIsOn() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let preference = HiddenFilesPreference(defaults: defaults)
        preference.showHiddenFiles = true

        let controller = ViewerWindowController(
            fileURL: visible,
            defaults: defaults,
            hiddenFilesPreference: preference,
            perFileState: PerFileStateStore(defaults: defaults)
        )
        defer { controller.close() }

        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains(".hidden.mmd"))
        #expect(controller.fileListModel.showHiddenFiles)
    }

    @Test("hiddenFilesPreference.showHiddenFiles が false(デフォルト)のとき不可視ファイルは含まれない")
    func sidebarExcludesHiddenFilesWhenPreferenceIsOff() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let preference = HiddenFilesPreference(defaults: defaults)

        let controller = ViewerWindowController(
            fileURL: visible,
            defaults: defaults,
            hiddenFilesPreference: preference,
            perFileState: PerFileStateStore(defaults: defaults)
        )
        defer { controller.close() }

        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(!names.contains(".hidden.mmd"))
        #expect(!controller.fileListModel.showHiddenFiles)
    }

    @Test("ファイル別の frameAutosaveName は設定されない")
    func noPerFileFrameAutosave() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")

        let controller = makeController(file: file)
        defer { controller.close() }

        #expect(controller.windowFrameAutosaveName == "")
    }

    @Test("保存されたフレームがなければデフォルトのコンテンツサイズで開く")
    func windowOpensAtDefaultSizeWithoutSavedFrame() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")

        let controller = makeController(file: file)
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

        let first = makeController(file: file, zoomStore: zoomStore, defaults: defaults)
        defer { first.close() }
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        first.window?.setFrame(frame, display: false)
        first.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        let second = makeController(file: file, zoomStore: zoomStore, defaults: defaults)
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

        let first = makeController(file: file, zoomStore: zoomStore, defaults: defaults)
        let frame = NSRect(x: 160, y: 180, width: 800, height: 650)
        first.window?.setFrame(frame, display: false)
        first.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        first.close()

        let second = makeController(file: file, zoomStore: zoomStore, defaults: defaults)
        defer { second.close() }

        #expect(second.window?.frame == frame)
    }

    @Test("windowDidBecomeKey でデリゲートが呼ばれる")
    func windowDidBecomeKeyInvokesDelegate() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        #expect(mock.becomeKeyCalled)
    }

    @Test("switchFile でファイル URL とウィンドウタイトルが更新される")
    func switchFileUpdatesFileURLAndTitle() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
        let controller = makeController(file: file1)
        defer { controller.close() }

        controller.switchFile(to: file2)

        #expect(controller.fileURL == file2)
        #expect(controller.window?.title == "second.mmd")
        #expect(controller.window?.representedURL == file2)
    }

    @Test("switchFile でデリゲートに旧・新 URL が通知される")
    func switchFileInvokesDelegate() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
        let controller = makeController(file: file1)
        defer { controller.close() }
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock

        controller.switchFile(to: file2)

        #expect(mock.switchFileArgs?.old == file1)
        #expect(mock.switchFileArgs?.new == file2)
    }

    @Test("switchFile で同じファイルを選んでも何も起きない")
    func switchFileIgnoresSameFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock

        controller.switchFile(to: file)

        #expect(mock.switchFileArgs == nil)
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
        let controller = makeController(file: file1, zoomStore: zoomStore, defaults: defaults)
        defer { controller.close() }

        controller.switchFile(to: file2)

        // 切替はリネームではないため、双方の保存倍率が独立して保たれる。
        #expect(zoomStore.zoom(for: file1) == 2.0)
        #expect(zoomStore.zoom(for: file2) == 0.75)
    }

    @Test("rename でサイドバーの一覧が再取得され新名が選択される")
    func renameRefreshesSidebarListAndSelection() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "old.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let renamed = tmp.url.appendingPathComponent("new.mmd")
        try FileManager.default.moveItem(at: file, to: renamed)

        // 本番では ViewerStore が現在 URL(store.currentURL)を新パスへ進めてから
        // controller.handleRename を呼ぶ。その順序を再現するため store を先に進める。
        controller.store.openFile(renamed)
        controller.handleRename(from: file, to: renamed)
        await controller.sidebar.pendingListingTask?.value

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
        let controller = makeController(file: file)
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = tmp.url.appendingPathComponent("note.markdown")
        try FileManager.default.moveItem(at: file, to: renamed)

        controller.handleRename(from: controller.fileURL, to: renamed)

        #expect(controller.isSourceMode)
    }

    @Test("非対応形式への rename ではソース表示が解除される")
    func renameToNonRenderableResetsSourceMode() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
        let controller = makeController(file: file)
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = tmp.url.appendingPathComponent("note.swift")
        try FileManager.default.moveItem(at: file, to: renamed)

        controller.handleRename(from: controller.fileURL, to: renamed)

        // .swift は isRenderable == false のため、ソース表示トグルが成立せずリセットする。
        #expect(!controller.isSourceMode)
    }

    @Test("navigateToFolder でカレントディレクトリと一覧が更新される")
    func navigateToFolderUpdatesCurrentDirectoryAndEntries() async throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = ViewerWindowController(
            fileURL: file,
            perFileState: PerFileStateStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
        )
        defer { controller.close() }

        controller.navigateToFolder(subDir)
        await controller.sidebar.pendingListingTask?.value

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
        let controller = makeController(file: file)
        defer { controller.close() }

        controller.navigateToFolder(tmp.url)

        #expect(controller.fileListModel.currentDirectory.standardizedFileURL == tmp.url.standardizedFileURL)
    }

    @Test("navigateToFolder はホームディレクトリより上には移動しない")
    func navigateToFolderRefusesAboveHomeDirectory() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let before = controller.fileListModel.currentDirectory
        let aboveHome = FileManager.default.homeDirectoryForCurrentUser
            .deletingLastPathComponent()

        controller.navigateToFolder(aboveHome)

        #expect(controller.fileListModel.currentDirectory == before)
    }

    @Test("子フォルダーへの移動では自動選択されない")
    func navigateToChildDoesNotAutoSelect() async throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let grandChild = subDir.appendingPathComponent("grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: grandChild, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = makeController(file: file)
        defer { controller.close() }

        controller.navigateToFolder(subDir)
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.selection == nil)
    }

    @Test("子フォルダーへの移動ではファイルが自動的に開かれない")
    func navigateToChildDoesNotAutoOpenFile() async throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = makeController(file: file)
        defer { controller.close() }

        controller.navigateToFolder(subDir)
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileURL.lastPathComponent == "diagram.mmd")
    }

    @Test("ファイルのない子フォルダーへの移動では何も選択されない")
    func navigateToChildWithoutFilesClearsSelection() async throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let grandChild = subDir.appendingPathComponent("grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: grandChild, withIntermediateDirectories: true)
        let controller = makeController(file: file)
        defer { controller.close() }

        controller.navigateToFolder(subDir)
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.selection == nil)
    }

    @Test("親フォルダーへの移動では直前の子フォルダーが選択される")
    func navigateToParentSelectsPreviousChild() async throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let file = try tmp.file(named: "sub/child.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }

        controller.navigateToFolder(tmp.url)
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.selection?.lastPathComponent == "sub")
    }
}

// MARK: - Navigation History

/// SwiftLint の type_body_length(error: 350) を超えないよう、履歴系テストは
/// 同一スイート(ViewerWindowControllerTests)の extension として分離する。
/// Swift Testing は @Suite 型の extension 内の @Test も同一スイートとして検出する。
extension ViewerWindowControllerTests {
    @Test("初期状態では戻る履歴がない")
    func historyStartsEmpty() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = makeController(file: file, defaults: makeIsolatedDefaults(prefix: "History"))
        defer { controller.close() }

        #expect(controller.fileListModel.canGoBack == false)
        #expect(controller.fileListModel.canGoForward == false)
    }

    @Test("switchFile で履歴が積まれ戻ると元ファイルに復帰する")
    func switchFilePushesHistoryAndBackRestores() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "b.mmd", contents: "graph LR;")
        let fileB = fileA.deletingLastPathComponent().appendingPathComponent("b.mmd")
        let controller = makeController(file: fileA, defaults: makeIsolatedDefaults(prefix: "History"))
        defer { controller.close() }

        controller.switchFile(to: fileB)
        #expect(controller.fileURL.lastPathComponent == "b.mmd")
        #expect(controller.fileListModel.canGoBack == true)

        controller.navigateHistory(by: -1)
        #expect(controller.fileURL.lastPathComponent == "a.mmd")
        #expect(controller.fileListModel.canGoForward == true)
        #expect(controller.fileListModel.canGoBack == false)
    }

    @Test("戻る操作自体は新しい履歴を積まない")
    func navigatingHistoryDoesNotRecord() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "b.mmd", contents: "graph LR;")
        let fileB = fileA.deletingLastPathComponent().appendingPathComponent("b.mmd")
        let controller = makeController(file: fileA, defaults: makeIsolatedDefaults(prefix: "History"))
        defer { controller.close() }
        controller.switchFile(to: fileB)

        controller.navigateHistory(by: -1) // a へ戻る
        controller.navigateHistory(by: 1) // b へ進む

        // 破棄されずに往復できる = 戻る/進むで push されていない
        #expect(controller.fileURL.lastPathComponent == "b.mmd")
        #expect(controller.fileListModel.canGoForward == false)
        #expect(controller.fileListModel.canGoBack == true)
    }

    @Test("戻る/進むメニューは対応する履歴があるときだけ有効")
    func goBackAndForwardMenuValidation() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let fileB = try tmp.file(named: "b.mmd", contents: "graph TD;")
        let controller = makeController(file: fileA)
        defer { controller.close() }
        let backItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.goBack(_:)), keyEquivalent: ""
        )
        let forwardItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.goForward(_:)), keyEquivalent: ""
        )

        #expect(controller.validateMenuItem(backItem) == false)
        #expect(controller.validateMenuItem(forwardItem) == false)

        controller.switchFile(to: fileB)
        #expect(controller.validateMenuItem(backItem) == true)
        #expect(controller.validateMenuItem(forwardItem) == false)

        controller.navigateHistory(by: -1)
        #expect(controller.validateMenuItem(backItem) == false)
        #expect(controller.validateMenuItem(forwardItem) == true)
    }

    @Test("ブックマークメニューはブックマーク状態に応じてタイトルが切り替わる")
    func toggleBookmarkMenuItemTitleReflectsState() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let bookmarkItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.toggleBookmark(_:)), keyEquivalent: ""
        )

        #expect(controller.validateMenuItem(bookmarkItem) == true)
        #expect(bookmarkItem.title == String(localized: "menu.view.addBookmark", bundle: .l10n))

        controller.toggleBookmark(nil)

        #expect(controller.validateMenuItem(bookmarkItem) == true)
        #expect(bookmarkItem.title == String(localized: "menu.view.removeBookmark", bundle: .l10n))
    }
}

// MARK: - handleOpenReference (Link Navigation)

/// リンククリック(JS の referenceActivated → handleOpenReference)経由の履歴記録・
/// サイドバー追従は switchFile 内の sidebar.syncAfterSwitch が既に行っている(実機確認済み)。
/// この既存挙動を回帰テストとして固定する。
extension ViewerWindowControllerTests {
    @Test("リンク遷移で履歴が積まれ、戻る操作で復帰する")
    func handleOpenReferenceRecordsHistoryAndBackRestores() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.md", contents: "# A")
        _ = try tmp.file(named: "b.md", contents: "# B")
        let controller = makeController(file: fileA, defaults: makeIsolatedDefaults(prefix: "OpenReference"))
        defer { controller.close() }

        controller.handleOpenReference(href: "b.md", newWindow: false)

        #expect(controller.fileURL.lastPathComponent == "b.md")
        #expect(controller.fileListModel.canGoBack == true)

        controller.navigateHistory(by: -1)

        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(controller.fileListModel.canGoForward == true)
    }

    @Test("別ディレクトリへのリンク遷移でサイドバーのディレクトリが追従し、戻ると復帰する")
    func handleOpenReferenceToOtherDirectoryFollowsSidebarAndBackRestores() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.md", contents: "# A")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        _ = try tmp.file(atPath: "sub/target.md", contents: "# Target")
        let controller = makeController(file: fileA, defaults: makeIsolatedDefaults(prefix: "OpenReference"))
        defer { controller.close() }
        let originalDirectory = controller.fileListModel.currentDirectory

        controller.handleOpenReference(href: "sub/target.md", newWindow: false)

        #expect(controller.fileURL.lastPathComponent == "target.md")
        #expect(controller.fileListModel.currentDirectory.standardizedFileURL == subDir.standardizedFileURL)

        controller.navigateHistory(by: -1)

        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(
            controller.fileListModel.currentDirectory.standardizedFileURL
                == originalDirectory.standardizedFileURL
        )
    }

    /// newWindow: true では AppDelegate.shared?.openViewer(for:) へ委譲するのみで、
    /// 現在のウィンドウ(controller)は switchFile を一切経由しない。テスト環境では
    /// AppDelegate.shared は nil(または新規ウィンドウを開けない)ため実際に新規ウィンドウが
    /// 開くかまでは検証できないが、本テストが固定したいのは「元ウィンドウの表示ファイル・履歴が
    /// 変化しないこと」であり、それはこの環境でも確実に検証できる。
    @Test("newWindow: true 経路では元ウィンドウの状態が変化しない")
    func handleOpenReferenceWithNewWindowLeavesOriginalWindowUnchanged() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.md", contents: "# A")
        _ = try tmp.file(named: "b.md", contents: "# B")
        let controller = makeController(file: fileA, defaults: makeIsolatedDefaults(prefix: "OpenReference"))
        defer { controller.close() }

        controller.handleOpenReference(href: "b.md", newWindow: true)

        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(controller.fileListModel.canGoBack == false)
        #expect(controller.fileListModel.selection?.lastPathComponent == "a.md")
    }
}
