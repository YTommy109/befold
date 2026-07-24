import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
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

/// ViewerWindowController のうち、実ファイルシステムに依存しない振る舞い
/// (ウィンドウフレーム記録・デリゲート通知・メニュー状態など)を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入し、directoryLister も差し替えて
/// 実 FS を使わない。実 rename/switch/navigate/隠しファイルフィルタに依存するテストは
/// ViewerWindowControllerIntegrationTests へ移した。
@Suite
@MainActor
struct ViewerWindowControllerTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")

    /// サイドバー初期一覧の取得を実 FS に触れさせないための空リスター。
    private let noEntries: (URL, befold.SortOrder, Bool) -> [FileListEntry] = { _, _, _ in [] }

    /// 実ファイル内容・実 watcher を必要としない、モック済みの ViewerStore を作る。
    private func makeMockStore(defaults: UserDefaults, contents: String = "graph TD;") -> ViewerStore {
        ViewerStore(
            watcherFactory: { _, _, _ in MockFileWatcher() },
            fileReader: InMemoryFileReader(files: [file.path: contents]),
            defaults: defaults
        )
    }

    /// テスト用に隔離済み UserDefaults とモック済み store / directoryLister を注入したコントローラーを作る。
    private func makeController(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
    ) -> ViewerWindowController {
        ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: makeMockStore(defaults: defaults),
            directoryLister: noEntries
        )
    }

    @Test("ファイル別の frameAutosaveName は設定されない")
    func noPerFileFrameAutosave() {
        let controller = makeController()
        defer { controller.close() }

        #expect(controller.windowFrameAutosaveName == "")
    }

    @Test("保存されたフレームがなければデフォルトのコンテンツサイズで開く")
    func windowOpensAtDefaultSizeWithoutSavedFrame() {
        let controller = makeController()
        defer { controller.close() }

        let contentSize = controller.window.map {
            $0.contentRect(forFrameRect: $0.frame).size
        } ?? .zero
        #expect(contentSize == NSSize(width: 1100, height: 850))
    }

    // フレームの「次のウィンドウへの引き継ぎ」自体は ViewerWindowManager.openViewer が
    // WindowFrameStore を介して解決する(ViewerWindowManagerIntegrationTests 参照)。ここでは
    // ViewerWindowController 自身の責務、すなわち (1) リサイズ/クローズ時に
    // WindowFrameStore へ記録すること、(2) 注入された initialFrameDescriptor を
    // 実際のウィンドウへ適用すること、を検証する。

    @Test("リサイズ完了時に WindowFrameStore へフレームが記録される")
    func windowFrameIsRecordedOnResize() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults, perFileState: perFileState,
            store: makeMockStore(defaults: defaults), directoryLister: noEntries
        )
        defer { controller.close() }
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        controller.window?.setFrame(frame, display: false)

        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        #expect(perFileState.windowFrame.frameDescriptor(for: file) == controller.window?.frameDescriptor)
    }

    @Test("ウィンドウを閉じたときにも WindowFrameStore へフレームが記録される")
    func windowFrameIsRecordedOnClose() throws {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults, perFileState: perFileState,
            store: makeMockStore(defaults: defaults), directoryLister: noEntries
        )
        let frame = NSRect(x: 160, y: 180, width: 800, height: 650)
        controller.window?.setFrame(frame, display: false)
        let descriptor = try #require(controller.window?.frameDescriptor)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        controller.close()

        #expect(perFileState.windowFrame.frameDescriptor(for: file) == descriptor)
    }

    @Test("initialFrameDescriptor を渡すとそのフレームで開く")
    func windowUsesInjectedInitialFrameDescriptor() throws {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let first = makeController(defaults: defaults)
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        first.window?.setFrame(frame, display: false)
        let descriptor = try #require(first.window?.frameDescriptor)
        first.close()

        let second = ViewerWindowController(
            fileURL: file, defaults: defaults, perFileState: PerFileStateStore(defaults: defaults),
            initialFrameDescriptor: descriptor,
            store: makeMockStore(defaults: defaults), directoryLister: noEntries
        )
        defer { second.close() }

        #expect(second.window?.frame == frame)
    }

    @Test("windowDidBecomeKey でデリゲートが呼ばれる")
    func windowDidBecomeKeyInvokesDelegate() {
        let controller = makeController()
        defer { controller.close() }
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        #expect(mock.becomeKeyCalled)
    }

    @Test("switchFile で同じファイルを選んでも何も起きない")
    func switchFileIgnoresSameFile() {
        let controller = makeController()
        defer { controller.close() }
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock

        controller.switchFile(to: file)

        #expect(mock.switchFileArgs == nil)
    }

    @Test("初期状態では戻る履歴がない")
    func historyStartsEmpty() {
        let controller = makeController(defaults: makeIsolatedDefaults(prefix: "History"))
        defer { controller.close() }

        #expect(controller.fileListModel.canGoBack == false)
        #expect(controller.fileListModel.canGoForward == false)
    }

    @Test("ブックマークメニューはブックマーク状態に応じてタイトルが切り替わる")
    func toggleBookmarkMenuItemTitleReflectsState() {
        let controller = makeController()
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
