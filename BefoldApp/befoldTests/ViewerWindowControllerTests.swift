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
    var toggleChangedFilesOnlyCalled = false

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

    func viewerWindowDidToggleChangedFilesOnly(_ controller: ViewerWindowController) {
        toggleChangedFilesOnlyCalled = true
    }
}

/// ViewerWindowController のうち、実ファイルシステムに依存しない振る舞い
/// (ウィンドウフレーム記録・デリゲート通知・メニュー状態など)を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入して
/// 実 FS を使わない。実 rename/switch/navigate/隠しファイルフィルタに依存するテストは
/// ViewerWindowControllerIntegrationTests へ移した。
/// コンテンツペインはプレースホルダ(ViewerWindowControllerFixture)のため、
/// WebView に依存する検証(検索・印刷・ズームなど)はこのスイートに置かない。
@Suite
@MainActor
struct ViewerWindowControllerTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")

    /// テスト用に隔離済み UserDefaults とモック済み store(実 WKWebView 無し)を注入したコントローラーを作る。
    private func makeController(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(file: file, defaults: defaults).controller
    }

    /// 互いに独立した(状態を共有・変更し合わない)初期状態の検証をまとめて
    /// 1つのウィンドウ生成で行う: frameAutosaveName 未設定・デフォルトコンテンツサイズ・
    /// windowDidBecomeKey 通知・switchFile の同一ファイル無視・初期履歴が空・
    /// ブックマークメニューのトグル。
    @Test("新規ウィンドウの初期状態(フレーム・デリゲート通知・履歴・メニュー)を検証する")
    func newWindowInitialState() {
        let controller = makeController()
        defer { controller.close() }

        // ファイル別の frameAutosaveName は設定されない
        #expect(controller.windowFrameAutosaveName == "")

        // 保存されたフレームがなければデフォルトのコンテンツサイズで開く
        let contentSize = controller.window.map {
            $0.contentRect(forFrameRect: $0.frame).size
        } ?? .zero
        #expect(contentSize == NSSize(width: 1100, height: 850))

        // windowDidBecomeKey でデリゲートが呼ばれる
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(mock.becomeKeyCalled)

        // switchFile で同じファイルを選んでも何も起きない
        controller.switchFile(to: file)
        #expect(mock.switchFileArgs == nil)

        // 初期状態では戻る履歴がない
        #expect(controller.fileListModel.canGoBack == false)
        #expect(controller.fileListModel.canGoForward == false)

        // ブックマークメニューはブックマーク状態に応じてタイトルが切り替わる
        let bookmarkItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.toggleBookmark(_:)), keyEquivalent: ""
        )
        #expect(controller.validateMenuItem(bookmarkItem) == true)
        #expect(bookmarkItem.title == String(localized: "menu.view.addBookmark", bundle: .l10n))
        controller.toggleBookmark(nil)
        #expect(controller.validateMenuItem(bookmarkItem) == true)
        #expect(bookmarkItem.title == String(localized: "menu.view.removeBookmark", bundle: .l10n))
    }

    // フレームの「次のウィンドウへの引き継ぎ」自体は ViewerWindowManager.openViewer が
    // WindowFrameStore を介して解決する(ViewerWindowManagerIntegrationTests 参照)。ここでは
    // ViewerWindowController 自身の責務、すなわち (1) リサイズ/クローズ時に
    // WindowFrameStore へ記録すること、(2) 注入された initialFrameDescriptor を
    // 実際のウィンドウへ適用すること、を検証する。

    @Test("リサイズ完了時に WindowFrameStore へフレームが記録される")
    func windowFrameIsRecordedOnResize() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let fixture = ViewerWindowControllerFixture(file: file, defaults: defaults)
        let controller = fixture.controller
        defer { controller.close() }
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        controller.window?.setFrame(frame, display: false)

        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        #expect(fixture.perFileState.windowFrame.frameDescriptor(for: file) == controller.window?.frameDescriptor)
    }

    @Test("ウィンドウを閉じたときにも WindowFrameStore へフレームが記録される")
    func windowFrameIsRecordedOnClose() throws {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let fixture = ViewerWindowControllerFixture(file: file, defaults: defaults)
        let controller = fixture.controller
        let frame = NSRect(x: 160, y: 180, width: 800, height: 650)
        controller.window?.setFrame(frame, display: false)
        let descriptor = try #require(controller.window?.frameDescriptor)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        controller.close()

        #expect(fixture.perFileState.windowFrame.frameDescriptor(for: file) == descriptor)
    }

    @Test("initialFrameDescriptor を渡すとそのフレームで開く")
    func windowUsesInjectedInitialFrameDescriptor() throws {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let first = makeController(defaults: defaults)
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        first.window?.setFrame(frame, display: false)
        let descriptor = try #require(first.window?.frameDescriptor)
        first.close()

        let second = ViewerWindowControllerFixture(
            file: file, defaults: defaults, initialFrameDescriptor: descriptor
        ).controller
        defer { second.close() }

        #expect(second.window?.frame == frame)
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
        openFileElsewhere: @escaping (URL, OpenDisposition, NSWindow?) -> Void = { _, _, _ in },
        externalOpener: @escaping (URL) -> Void = { _ in }
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: primary,
            extraFiles: others,
            contents: contents,
            defaults: defaults,
            zoomStore: zoomStore,
            openFileElsewhere: openFileElsewhere,
            externalOpener: externalOpener
        ).controller
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

    @Test("rename 先の拡張子が対応形式かどうかでソース表示の維持/解除が決まる", arguments: [
        ("note.markdown", true), // 対応形式への rename ではソース表示が維持される
        // .swift は supportsSourceMode == false のため、ソース表示トグルが成立せずリセットする。
        ("note.swift", false), // 非対応形式への rename ではソース表示が解除される
    ])
    func renameChangesSourceModeByRenderability(renamedFilename: String, expectedSourceMode: Bool) {
        let file = URL(fileURLWithPath: "/mock/note.md")
        let controller = makeSwitchController(primary: file, contents: "# hi")
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = URL(fileURLWithPath: "/mock/\(renamedFilename)")

        controller.handleRename(from: controller.fileURL, to: renamed)

        #expect(controller.isSourceMode == expectedSourceMode)
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

    /// 外部 URL(http/https)のコンテキストメニュー「開く」系は、ファイルビューア経路
    /// (switchFile/openFileElsewhere)に流すと存在確認に失敗して「ファイルが見つかりません」に
    /// なる(review 指摘)。修飾キーによらずブラウザで開くことをここで固定する。
    @Test("外部 URL のコンテキストメニュー「開く」はファイルビューア経路を経由しない")
    func externalURLContextMenuOpenSkipsFileViewer() throws {
        let file = URL(fileURLWithPath: "/mock/a.md")
        var openedElsewhere: [URL] = []
        var openedExternally: [URL] = []
        let controller = makeSwitchController(
            primary: file,
            defaults: makeIsolatedDefaults(prefix: "ExternalURLContextMenu"),
            openFileElsewhere: { url, _, _ in openedElsewhere.append(url) },
            externalOpener: { url in openedExternally.append(url) }
        )
        defer { controller.close() }
        let externalURL = try #require(URL(string: "https://example.com/docs"))

        for disposition: OpenDisposition in [.currentTab, .newTab, .newWindow] {
            let menu = ReferenceContextMenu.makeMenu(
                for: externalURL, isExternal: true, target: controller,
                action: Selector(("performReferenceMenuAction:"))
            )
            let openItem = menu.items.first {
                ($0.representedObject as? ReferenceMenuInvocation)?.action == .open(disposition)
            }
            _ = openItem?.target?.perform(openItem?.action, with: openItem)
        }

        #expect(openedElsewhere.isEmpty)
        // switchFile 経由(.currentTab)なら fileURL が書き換わるが、外部 URL では現在ファイルのまま。
        #expect(controller.fileURL == file)
        // 3 disposition すべてで、実ブラウザを起動せず externalOpener 経由でブラウザ経路に渡ったことを確認する。
        #expect(openedExternally == [externalURL, externalURL, externalURL])
    }
}
