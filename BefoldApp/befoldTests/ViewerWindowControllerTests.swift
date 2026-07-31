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

    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController) {
        toggleHiddenFilesCalled = true
    }
}

/// ViewerWindowController のうち、実ファイルシステムに依存しない振る舞い
/// (ウィンドウフレーム記録・デリゲート通知・メニュー状態など)を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入して
/// 実 FS を使わない。実 rename/switch/navigate/隠しファイルフィルタに依存するテストは
/// ViewerWindowControllerIntegrationTests へ移した。
@Suite
@MainActor
struct ViewerWindowControllerTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")

    /// 実ファイル内容・実 watcher を必要としない、モック済みの ViewerStore を作る。
    private func makeMockStore(defaults: UserDefaults, contents: String = "graph TD;") -> ViewerStore {
        ViewerStore(
            watcherFactory: { _, _, _ in MockFileWatcher() },
            fileReader: InMemoryFileReader(files: [file.path: contents]),
            defaults: defaults
        )
    }

    /// テスト用に隔離済み UserDefaults とモック済み store を注入したコントローラーを作る。
    private func makeController(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
    ) -> ViewerWindowController {
        ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: makeMockStore(defaults: defaults)
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
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: makeMockStore(defaults: defaults)
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
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: makeMockStore(defaults: defaults)
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
            bookmarkStore: BookmarkStore(defaults: defaults),
            initialFrameDescriptor: descriptor,
            store: makeMockStore(defaults: defaults)
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

// MARK: - switch / rename / history / handleOpenReference

/// switchFile / performFileSwitch / handleOpenReference の存在ガードが store.fileReader 経由に
/// なった(TASK-116.12)ため、切替・リンク遷移・履歴の振る舞いも InMemoryFileReader でモック化して
/// unit で検証する。サイドバー一覧の実列挙・実 rename の再一覧に依存するテストは
/// ViewerWindowControllerIntegrationTests に残す。
extension ViewerWindowControllerTests {
    /// 複数ファイルを InMemoryFileReader に登録した store を持つコントローラーを作る。
    /// primary が初期表示ファイル、others は switch/リンク先として存在確認を通すために登録する。
    private func makeSwitchController(
        primary: URL,
        others: [URL] = [],
        contents: String = "graph TD;",
        zoomStore: ZoomStore? = nil,
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"),
        openFileElsewhere: @escaping (URL, OpenDisposition, NSWindow?) -> Void = { _, _, _ in }
    ) -> ViewerWindowController {
        var dict: [String: String] = [:]
        for url in [primary] + others {
            dict[url.path] = contents
        }
        return ViewerWindowController(
            fileURL: primary,
            defaults: defaults,
            perFileState: PerFileStateStore(
                zoom: zoomStore ?? ZoomStore(defaults: defaults),
                sourceMode: SourceModeStore(defaults: defaults),
                scrollPosition: ScrollPositionStore(defaults: defaults),
                sidebar: SidebarStateStore(defaults: defaults),
                windowFrame: WindowFrameStore(defaults: defaults)
            ),
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: ViewerStore(
                watcherFactory: { _, _, _ in MockFileWatcher() },
                fileReader: InMemoryFileReader(files: dict),
                defaults: defaults
            ),
            openFileElsewhere: openFileElsewhere
        )
    }

    @Test("switchFile でファイル URL とウィンドウタイトルが更新される")
    func switchFileUpdatesFileURLAndTitle() {
        let file1 = URL(fileURLWithPath: "/mock/first.mmd")
        let file2 = URL(fileURLWithPath: "/mock/second.mmd")
        let controller = makeSwitchController(primary: file1, others: [file2])
        defer { controller.close() }

        controller.switchFile(to: file2)

        #expect(controller.fileURL == file2)
        #expect(controller.window?.title == "second.mmd")
        #expect(controller.window?.representedURL == file2)
    }

    @Test("switchFile でデリゲートに旧・新 URL が通知される")
    func switchFileInvokesDelegate() {
        let file1 = URL(fileURLWithPath: "/mock/first.mmd")
        let file2 = URL(fileURLWithPath: "/mock/second.mmd")
        let controller = makeSwitchController(primary: file1, others: [file2])
        defer { controller.close() }
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock

        controller.switchFile(to: file2)

        #expect(mock.switchFileArgs?.old == file1)
        #expect(mock.switchFileArgs?.new == file2)
    }

    @Test("switchFile は旧・新ファイルの保存済み倍率を破壊しない")
    func switchFilePreservesSavedZoomForBothFiles() {
        let file1 = URL(fileURLWithPath: "/mock/first.mmd")
        let file2 = URL(fileURLWithPath: "/mock/second.mmd")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let zoomStore = ZoomStore(defaults: defaults)
        zoomStore.setZoom(2.0, for: file1)
        zoomStore.setZoom(0.75, for: file2)
        let controller = makeSwitchController(
            primary: file1, others: [file2], zoomStore: zoomStore, defaults: defaults
        )
        defer { controller.close() }

        controller.switchFile(to: file2)

        // 切替はリネームではないため、双方の保存倍率が独立して保たれる。
        #expect(zoomStore.zoom(for: file1) == 2.0)
        #expect(zoomStore.zoom(for: file2) == 0.75)
    }

    @Test("対応形式への rename ではソース表示が維持される")
    func renameToRenderableKeepsSourceMode() {
        let file = URL(fileURLWithPath: "/mock/note.md")
        let controller = makeSwitchController(primary: file, contents: "# hi")
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = URL(fileURLWithPath: "/mock/note.markdown")

        controller.handleRename(from: controller.fileURL, to: renamed)

        #expect(controller.isSourceMode)
    }

    @Test("非対応形式への rename ではソース表示が解除される")
    func renameToNonRenderableResetsSourceMode() {
        let file = URL(fileURLWithPath: "/mock/note.md")
        let controller = makeSwitchController(primary: file, contents: "# hi")
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = URL(fileURLWithPath: "/mock/note.swift")

        controller.handleRename(from: controller.fileURL, to: renamed)

        // .swift は supportsSourceMode == false のため、ソース表示トグルが成立せずリセットする。
        #expect(!controller.isSourceMode)
    }

    @Test("switchFile で履歴が積まれ戻ると元ファイルに復帰する")
    func switchFilePushesHistoryAndBackRestores() {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeSwitchController(
            primary: fileA, others: [fileB], defaults: makeIsolatedDefaults(prefix: "History")
        )
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
    func navigatingHistoryDoesNotRecord() {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeSwitchController(
            primary: fileA, others: [fileB], defaults: makeIsolatedDefaults(prefix: "History")
        )
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
    func goBackAndForwardMenuValidation() {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeSwitchController(primary: fileA, others: [fileB])
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

    @Test("リンク遷移で履歴が積まれ、戻る操作で復帰する")
    func handleOpenReferenceRecordsHistoryAndBackRestores() async {
        let fileA = URL(fileURLWithPath: "/mock/a.md")
        let fileB = URL(fileURLWithPath: "/mock/b.md")
        let controller = makeSwitchController(
            primary: fileA, others: [fileB], contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "OpenReference")
        )
        defer { controller.close() }

        controller.handleOpenReference(href: "b.md", disposition: .currentTab)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(controller.fileURL.lastPathComponent == "b.md")
        #expect(controller.fileListModel.canGoBack == true)

        controller.navigateHistory(by: -1)

        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(controller.fileListModel.canGoForward == true)
    }

    @Test("resolveReferences は実在パスのみ解決済み絶対パスで返す")
    func resolveReferencesReturnsResolvedOnly() async {
        // 常に固定の追跡ファイル索引を返すフェイク。相対解決で見つからないパスの
        // git サフィックス一致フォールバックを検証するために使う。
        struct FakeGitIndex: GitFileIndexing {
            let tracked: URL
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                SuffixPathIndex(candidates: [tracked])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let tracked = URL(fileURLWithPath: "/mock/src/utils.swift")
        let controller = makeSwitchController(primary: base, contents: "# doc")
        defer { controller.close() }
        // utils.swift は書かれた相対位置(/mock/docs/utils.swift)には存在せず、
        // 追跡ファイルの実体(/mock/src/utils.swift)だけが存在する状態にする。
        // git サフィックス一致でのみ解決でき、かつ一致先は実在するという経路。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc", tracked.path: "// utils"]),
            gitIndex: FakeGitIndex(tracked: tracked)
        )

        let map = await controller.resolveReferences(["utils.swift", "https://example.com", "nope.swift"])

        #expect(map == ["utils.swift": tracked.path])
    }

    /// 表示時解決はキャッシュ未命中時に `git ls-files` の subprocess を待つ。
    /// MainActor 上で走ると大きなリポジトリで UI が数百 ms 止まるため、
    /// git 索引に触れるのがメインスレッド外であることを索引側から観測して固定する。
    @Test("表示時解決の git 索引アクセスはメインスレッド上で行われない")
    func resolveReferencesTouchesGitIndexOffMainThread() async {
        // 呼ばれたスレッドを記録するだけのフェイク索引。
        struct ThreadRecordingGitIndex: GitFileIndexing {
            let wasMainThread: LockedBox<Bool?>
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                wasMainThread.set(Thread.isMainThread)
                return SuffixPathIndex(candidates: [])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let wasMainThread = LockedBox<Bool?>(nil)
        let controller = makeSwitchController(
            primary: base, contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "ResolveOffMain")
        )
        defer { controller.close() }
        // 相対解決では見つからないパスを渡し、必ず git 索引フォールバックへ入らせる。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc"]),
            gitIndex: ThreadRecordingGitIndex(wasMainThread: wasMainThread)
        )

        _ = await controller.resolveReferences(["utils.swift"])

        #expect(wasMainThread.get() == false, "git 索引を MainActor 上で触っている")
    }

    /// クリック時解決(handleOpenReference)も表示時解決と同じく、キャッシュ未命中時は
    /// `git ls-files` の subprocess を待つ。resolveReferences と同じ方針で MainActor を
    /// 離して解決することを、git 索引側から観測して固定する(task-222 の回帰テスト)。
    @Test("クリック時解決の git 索引アクセスはメインスレッド上で行われない")
    func handleOpenReferenceTouchesGitIndexOffMainThread() async {
        struct ThreadRecordingGitIndex: GitFileIndexing {
            let wasMainThread: LockedBox<Bool?>
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                wasMainThread.set(Thread.isMainThread)
                return SuffixPathIndex(candidates: [])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let wasMainThread = LockedBox<Bool?>(nil)
        let controller = makeSwitchController(
            primary: base, contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "OpenReferenceOffMain")
        )
        defer { controller.close() }
        // 相対解決では見つからないパスを渡し、必ず git 索引フォールバックへ入らせる。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc"]),
            gitIndex: ThreadRecordingGitIndex(wasMainThread: wasMainThread)
        )

        controller.handleOpenReference(href: "utils.swift", disposition: .currentTab)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(wasMainThread.get() == false, "git 索引を MainActor 上で触っている")
    }

    /// 表示時解決とクリック時解決が同じ入力に一致することを固定する。
    /// 「リンク化したものは必ずそのリンク先へ開ける」がこの機能の中心的な不変条件であり、
    /// 現状は同じ pathResolver を通ることで成立しているが、片方だけを変える将来の変更で
    /// 静かに壊れうるため、実際の 2 経路を突き合わせて押さえる。
    @Test("表示時にリンク化した参照は、クリック時も同じ URL へ解決される")
    func resolveReferencesAndOpenReferenceAgreeOnGitFallback() async {
        struct FakeGitIndex: GitFileIndexing {
            let tracked: URL
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                SuffixPathIndex(candidates: [tracked])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let tracked = URL(fileURLWithPath: "/mock/src/utils.swift")
        var openedInNewWindow: [URL] = []
        let controller = makeSwitchController(
            primary: base, contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "ResolveAgreement"),
            openFileElsewhere: { url, _, _ in openedInNewWindow.append(url) }
        )
        defer { controller.close() }
        // 相対解決では見つからず、git 追跡ファイルのサフィックス一致でのみ解決できる状態。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc", tracked.path: "// utils"]),
            gitIndex: FakeGitIndex(tracked: tracked)
        )

        let resolved = await controller.resolveReferences(["utils.swift"])["utils.swift"]
        // disposition: .newWindow でクリックすると、開く先の URL がそのまま観測できる。
        controller.handleOpenReference(href: "utils.swift", disposition: .newWindow)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(resolved == tracked.path)
        #expect(openedInNewWindow.map(\.path) == [tracked.path])
        // 表示時にリンク化しなかった参照は、クリックしても遷移しない(逆方向の一致)。
        let unresolved = await controller.resolveReferences(["nope.swift"])
        #expect(unresolved.isEmpty)
        controller.handleOpenReference(href: "nope.swift", disposition: .newWindow)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value
        #expect(openedInNewWindow.map(\.path) == [tracked.path])
    }

    @Test("disposition: .newWindow 経路では元ウィンドウの状態が変化しない")
    func handleOpenReferenceWithNewWindowLeavesOriginalWindowUnchanged() async {
        let fileA = URL(fileURLWithPath: "/mock/a.md")
        let fileB = URL(fileURLWithPath: "/mock/b.md")
        var openedInNewWindow: [URL] = []
        let controller = makeSwitchController(
            primary: fileA, others: [fileB], contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "OpenReference"),
            openFileElsewhere: { url, _, _ in openedInNewWindow.append(url) }
        )
        defer { controller.close() }

        controller.handleOpenReference(href: "b.md", disposition: .newWindow)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        // 新規ウィンドウへの委譲のみで、現在のウィンドウは switchFile を経由しない。
        #expect(openedInNewWindow.map(\.lastPathComponent) == ["b.md"])
        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(controller.fileListModel.canGoBack == false)
    }

    /// disposition が openReference から openFileElsewhere まで書き換えられずに届くこと、
    /// かつタブ結合の基準になる自ウィンドウ(source)も一緒に渡ることを固定する。
    /// ここを捨てるスタブのままだと、.newTab と .newWindow の実装取り違えが
    /// 他のテストを緑のまま素通りしてしまう(review 指摘)。
    @Test("openReference は disposition と起点ウィンドウをそのまま openFileElsewhere へ渡す")
    func openReferencePassesDispositionAndSourceWindowThrough() async {
        let fileA = URL(fileURLWithPath: "/mock/a.md")
        let fileB = URL(fileURLWithPath: "/mock/b.md")
        var received: [(url: URL, disposition: OpenDisposition, source: NSWindow?)] = []
        let controller = makeSwitchController(
            primary: fileA, others: [fileB], contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "OpenReferenceDisposition"),
            openFileElsewhere: { url, disposition, source in
                received.append((url, disposition, source))
            }
        )
        defer { controller.close() }

        controller.handleOpenReference(href: "b.md", disposition: .newTab)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(received.map(\.url.lastPathComponent) == ["b.md"])
        #expect(received.map(\.disposition) == [.newTab])
        #expect(received.first?.source === controller.window)
    }
}
