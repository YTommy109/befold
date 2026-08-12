import AppKit
import BefoldCLI
import BefoldKit
import UserNotifications

/// アプリのライフサイクル(NSApplicationDelegate)と、メニュー/レスポンダチェーンから
/// 呼ばれる `@objc` アクションの受け口。
///
/// **ここは配線点であって実装置き場ではない。** 実際の仕事は責務ごとの型が持ち、
/// アクションはそこへ転送するだけにする。
///
/// - 文書を開く: `DocumentOpener`
/// - CLI 要求の受信: `AppCLIRequestReceiver` / CLI シムの設置: `CLIShimCoordinator`
/// - Quick Open: `QuickOpenCoordinator`
/// - 自動アップデート: `AppUpdaterController`
/// - 単一インスタンスのパネル: `AppDelegate+HostedPanels`
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate?
    /// アプリ全体で共有する永続化ストアと表示設定。束ねた 1 個を各機能へ配る。
    ///
    /// `private` にできないのは、`AppDelegate+HostedPanels` が設定パネルの組み立てで
    /// `codeFontPreference` を読むため(Swift の `private` はファイルスコープ)。
    /// **読んでよいのは同じ型グループの extension だけ**で、他の型からは
    /// init で渡された `AppStores` を通すこと。
    let stores: AppStores
    let windowManager: ViewerWindowManager
    private let sessionRestorer: SessionRestorer
    /// 単一インスタンスのパネルウィンドウ(About・設定・Help 配下)。初回のトグルで生成し、
    /// 以降は同じインスタンスを使い回す。
    var hostedPanels: [HostedPanel: HostedPanelWindowController] = [:]
    private let documentOpener: DocumentOpener
    private let quickOpen: QuickOpenCoordinator
    /// Sparkle の updater は delegate を weak で持つため、strong に保持し続ける必要がある
    /// (`AppUpdaterController` の doc を参照)。
    private let updater = AppUpdaterController()
    /// 生成と同時に購読が始まる。保持をやめると CLI からの起動要求が届かなくなる。
    private let cliRequestReceiver: AppCLIRequestReceiver
    private let mainMenu: MainMenuCoordinator

    override init() {
        let stores = AppStores()
        let windowManager = Self.makeWindowManager(stores: stores)
        let documentOpener = DocumentOpener(
            windowManager: windowManager,
            activeViewer: ActiveViewerProvider.fromMainWindow
        )
        let sessionRestorer = SessionRestorer(sessionStore: stores.sessionStore, windowManager: windowManager)
        self.stores = stores
        self.windowManager = windowManager
        self.documentOpener = documentOpener
        self.sessionRestorer = sessionRestorer
        quickOpen = QuickOpenCoordinator(
            stores: stores,
            gitIndex: windowManager.gitFileIndex,
            activeViewer: ActiveViewerProvider.fromMainWindow,
            openInNewWindow: { documentOpener.openViewer(for: $0) }
        )
        // 購読はここで始める。起動処理の後段へ倒すと、起動と同時に届いた CLI 要求の
        // ACK を取りこぼして再送を待たせることになる(AppCLIRequestReceiver の doc)。
        cliRequestReceiver = AppCLIRequestReceiver(
            onOpen: { paths, options in documentOpener.openPaths(paths, options: options) },
            onBookmark: { [windowManager] urls in windowManager.display.addBookmarks(for: urls) }
        )
        mainMenu = MainMenuCoordinator(
            stores: stores,
            sessionRestorer: sessionRestorer,
            openHandler: { documentOpener.openViewer(for: $0) }
        )
        super.init()
    }

    /// ウィンドウ生成の合成点。`GitStatusStore` の差し込みまで含めてここで組み立てる。
    private static func makeWindowManager(stores: AppStores) -> ViewerWindowManager {
        let windowManager = ViewerWindowManager(
            sessionStore: stores.sessionStore,
            recentDocumentsStore: stores.recentDocumentsStore,
            sidebarDisplayPreference: stores.sidebarDisplayPreference,
            diffDisplayPreference: stores.diffDisplayPreference,
            findOptionsPreference: stores.findOptionsPreference,
            codeFontPreference: stores.codeFontPreference,
            perFileState: stores.perFileState,
            bookmarkStore: stores.bookmarkStore,
            recentRepositoriesStore: stores.recentRepositoriesStore,
            // リポジトリを記録したら、その本体ルートの worktree 一覧も裏で解決し直しておく。
            // 次にメニューを開いた時点でキャッシュに載っていれば階層表示になる。
            onRepositoryRecorded: { [worktreeCatalog = stores.worktreeCatalog] mainRoot in
                Task { await worktreeCatalog.refresh(mainRoots: [mainRoot]) }
            }
        )
        // git 状態の取得は、ルート解決を全ウィンドウ共有の索引へ一本化する
        // (Store が独自に GitRepository を生成して rev-parse を重ねない)。
        // 索引の実体は windowManager が握っているため、生成後にここで差し込む。
        windowManager.gitStatusStore = GitStatusStore(
            resolveRepositoryRoot: { [gitFileIndex = windowManager.gitFileIndex] directory in
                gitFileIndex.repositoryRoot(forDirectoryAt: directory)
            }
        )
        return windowManager
    }

    nonisolated static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        AppDelegate.shared = delegate
        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = DocumentController()
        sessionRestorer.captureSavedState()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        stores.recentDocumentsStore.seedIfNeeded(with: NSDocumentController.shared.recentDocumentURLs)
        mainMenu.installMainMenu()
        UNUserNotificationCenter.current().delegate = self
        sessionRestorer.restoreLastSession()
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [windowManager] in
            ViewerTabGrouping.rescueWindowsDetachedFromSpace(
                among: windowManager.allControllers.compactMap(\.window)
            )
        }
        updater.start()
        CLIShimCoordinator.notifyIfStale()
        pruneRecentRepositories()
    }

    /// 「最近使ったリポジトリ」メニューは保存済みリストをそのまま表示するため、
    /// 存在しなくなった worktree 等の整理は起動時にここで1回だけ非同期に行う。
    /// 併せて、残ったエントリの本体ルートごとに worktree 一覧を解決してキャッシュへ載せる
    /// (メニュー表示時には git を呼ばず、このキャッシュを読むだけにするため)。
    private func pruneRecentRepositories() {
        Task { [recentRepositoriesStore = stores.recentRepositoriesStore, worktreeCatalog = stores.worktreeCatalog] in
            await recentRepositoriesStore.pruneMissingAsync()
            let mainRootPaths = Set(recentRepositoriesStore.entries().map { $0.mainRootPath ?? $0.rootPath })
            await worktreeCatalog.refresh(mainRoots: mainRootPaths.map { URL(fileURLWithPath: $0) })
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showOpenPanel()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        documentOpener.openSequentially(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let controller = ActiveViewerProvider.fromMainWindow() {
            stores.sessionStore.noteActivated(controller.fileURL)
        }
        // 終了時は windowWillClose が発火しないことがあるため、リポジトリ単位のタブ構成も
        // セッション全体のレイアウトと同じタイミングでスナップショットしておく。
        windowManager.recordAllRecentRepositoryTabGroups()
        stores.sessionStore.saveLayout(sessionRestorer.currentSessionLayout())
        stores.sessionStore.freeze()
        return .terminateNow
    }

    // MARK: - Actions

    /// 指定 URL のファイルをビューアウィンドウで開く(`DocumentController`・
    /// `ViewerWindowController` の参照クリックからも `AppDelegate.shared` 経由で呼ばれる)。
    func openViewer(for url: URL) {
        documentOpener.openViewer(for: url)
    }

    /// 参照クリック由来のオープン。
    func openViewer(for url: URL, disposition: OpenDisposition, relativeTo sourceWindow: NSWindow?) {
        documentOpener.openViewer(for: url, disposition: disposition, relativeTo: sourceWindow)
    }

    @objc func showOpenPanel() {
        documentOpener.presentOpenPanel()
    }

    /// Help > Visit Website。配布サイトをブラウザで開く。
    @objc func openHelp(_ sender: Any?) {
        NSWorkspace.shared.open(AppLinks.help)
    }

    @objc func showAbout(_ sender: Any?) {
        togglePanel(.about)
    }

    /// Help > 機能説明。
    @objc func showFeatureOverview(_ sender: Any?) {
        togglePanel(.featureOverview)
    }

    /// Help > キーボードショートカット。
    @objc func showKeyboardShortcuts(_ sender: Any?) {
        togglePanel(.keyboardShortcuts)
    }

    /// Help > AI コーディングエージェント連携。
    @objc func showAIIntegration(_ sender: Any?) {
        togglePanel(.aiIntegration)
    }

    /// Help > OSS 謝辞。
    @objc func showOSSLicenses(_ sender: Any?) {
        togglePanel(.ossLicenses)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates(sender)
    }

    /// メニューの「Install 'befold' command in PATH」。
    @objc func installCLI(_ sender: Any?) {
        CLIShimCoordinator.install()
    }

    /// View > Show/Hide Hidden Files(⌘⌃H)。不可視ファイル表示を全ウィンドウで一括切替する。
    @objc func toggleHiddenFiles(_ sender: Any?) {
        windowManager.display.toggleHiddenFiles()
    }

    /// View > Show Changed Files Only(⌘⌃G)。git 変更ファイルのみの絞り込みを全ウィンドウで一括切替する。
    @objc func toggleChangedFilesOnly(_ sender: Any?) {
        windowManager.display.toggleChangedFilesOnly()
    }

    /// View > サイドバーをツリー表示(ショートカットなし)。表示モードを全ウィンドウで一括切替する。
    @objc func toggleSidebarTreeLayout(_ sender: Any?) {
        windowManager.display.toggleSidebarLayoutMode()
    }

    /// App > Settings…(⌘,)。単一インスタンスで、
    /// 最前面なら閉じ、そうでなければ開く/前面化するトグル動作にする。
    @objc func showSettings(_ sender: Any?) {
        togglePanel(.settings)
    }

    /// File > Quick Open(⌘P)。パス入力と fuzzy 検索のパネルを開く。
    @objc func showQuickOpen(_ sender: Any?) {
        quickOpen.toggle()
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHiddenFiles(_:)) {
            menuItem.title = stores.sidebarDisplayPreference.showHiddenFiles
                ? String(localized: "menu.view.hideHiddenFiles", bundle: .l10n)
                : String(localized: "menu.view.showHiddenFiles", bundle: .l10n)
        }
        if menuItem.action == #selector(toggleChangedFilesOnly(_:)) {
            menuItem.state = stores.sidebarDisplayPreference.showChangedFilesOnly ? .on : .off
        }
        if menuItem.action == #selector(toggleSidebarTreeLayout(_:)) {
            menuItem.state = stores.sidebarDisplayPreference.layoutMode == .tree ? .on : .off
        }
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    /// befold 自身がフォアグラウンドの起動直後に通知を出すため、既定の抑制を解除してバナー表示させる。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
