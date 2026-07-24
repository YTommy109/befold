import AppKit
import BefoldCLI
import BefoldKit
import Sparkle
import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate?
    private let sessionStore: SessionStore
    private let windowManager: ViewerWindowManager
    private let hiddenFilesPreference: HiddenFilesPreference
    private let sessionRestorer: SessionRestorer
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private let recentDocumentsStore: RecentDocumentsStore
    private let bookmarkStore: BookmarkStore
    private var cliRequestDeduplicator = CLIRequestDeduplicator()
    private lazy var recentDocumentsMenuController = RecentDocumentsMenuController(
        recentURLs: { [weak self] in self?.recentDocumentsStore.recentURLs() ?? [] },
        openHandler: { [weak self] url in self?.openViewer(for: url) },
        clearHandler: { [weak self] in
            self?.recentDocumentsStore.clear()
            NSDocumentController.shared.clearRecentDocuments(nil)
        }
    )
    private lazy var bookmarksMenuController = BookmarksMenuController(
        bookmarkedURLs: { [weak self] in self?.bookmarkStore.bookmarkedURLs() ?? [] },
        openHandler: { [weak self] url in self?.openViewer(for: url) }
    )

    override init() {
        let sessionStore = SessionStore()
        let recentDocumentsStore = RecentDocumentsStore()
        let bookmarkStore = BookmarkStore()
        let hiddenFilesPreference = HiddenFilesPreference()
        let findOptionsPreference = FindOptionsPreference()
        let perFileState = PerFileStateStore()
        let windowManager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore
        )
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.bookmarkStore = bookmarkStore
        self.windowManager = windowManager
        self.hiddenFilesPreference = hiddenFilesPreference
        sessionRestorer = SessionRestorer(sessionStore: sessionStore, windowManager: windowManager)
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCLIOpenRequest(_:)),
            name: CLIInstanceRouter.openRequestNotificationName, object: nil
        )
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

    /// 別プロセスの CLI 起動から、起動中の当インスタンスへ転送されたオープン要求を処理する。
    /// forward() は ACK 未受信時に同じ requestID で再送するため、ACK は受信のたびに返すが、
    /// openPaths の実行は requestID ごとに一度だけに絞る。
    @objc private func handleCLIOpenRequest(_ notification: Notification) {
        guard let (paths, options) = CLIInstanceRouter.decode(userInfo: notification.userInfo) else { return }
        let requestID = CLIInstanceRouter.requestID(from: notification.userInfo)
        if let requestID {
            CLIInstanceRouter.sendAck(requestID: requestID)
        }
        guard cliRequestDeduplicator.shouldProcess(requestID: requestID) else { return }
        openPaths(paths, options: options)
        NSApp.activate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        recentDocumentsStore.seedIfNeeded(with: NSDocumentController.shared.recentDocumentURLs)
        NSApp.mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            helpAction: #selector(openHelp(_:)),
            recentMenuDelegate: recentDocumentsMenuController,
            bookmarksMenuDelegate: bookmarksMenuController
        )
        UNUserNotificationCenter.current().delegate = self
        sessionRestorer.restoreLastSession()
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [windowManager] in
            windowManager.rescueWindowsDetachedFromSpace()
        }
        #if DEBUG
            updaterController.updater.automaticallyChecksForUpdates = false
        #endif
        do {
            try updaterController.updater.start()
        } catch {
            NSLog("Sparkle updater failed to start: %@", error.localizedDescription)
        }
        if updaterController.updater.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
        notifyIfCLIShimIsStale()
    }

    /// 起動時に一度だけ /usr/local/bin/befold の状態を読み取り専用でチェックし、
    /// 古い実体ファイル/参照先不一致の symlink が残っている場合のみ再インストールを案内する。
    /// 書き込み(再インストール自体)は行わない。
    ///
    /// 状態チェックのファイル I/O はバックグラウンドキューへ逃がし、起動処理(ウィンドウ復元・
    /// メニュー構築)をブロックしない。案内も app-modal な `runModal()` ではなく通知センターの
    /// バナー通知で表示し、表示中も CLI 転送の ACK 応答が main run loop 上で通常どおり
    /// 処理され続けるようにする。
    private func notifyIfCLIShimIsStale() {
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.global(qos: .utility).async {
            let status = CLIShimInspector.status(bundlePath: bundlePath, installPath: CLIInstaller.defaultInstallPath)
            guard status == .legacyFile || status == .staleSymlink else { return }
            Task { @MainActor in
                await CLIInstallUI.presentReinstallRecommended()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showOpenPanel()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openViewer(for: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let keyWindow = NSApp.keyWindow,
           let controller = keyWindow.windowController as? ViewerWindowController
        {
            sessionStore.noteActivated(controller.fileURL)
        }
        sessionStore.saveLayout(sessionRestorer.currentSessionLayout())
        sessionStore.freeze()
        return .terminateNow
    }

    // MARK: - Actions

    /// 指定 URL のファイルをビューアウィンドウで開く(DocumentController・Recent メニューからも呼ばれる)。
    /// ディレクトリが渡された場合は、フォルダー内最初のファイルを開く(CLI シム経由の想定)。
    /// 拡張子を問わずウィンドウは開かれ、未対応の内容ならビューア側でプレースホルダー表示する。
    func openViewer(for url: URL) {
        openViewer(for: url, options: CLIOpenOptions())
    }

    /// CLI から渡されたパス群を、表示オプション付きでそれぞれ別ウィンドウに開く。
    /// `--hidden-files`/`--no-hidden-files` はウィンドウ単位ではなくアプリ全体の設定のため、先に一度だけ反映する。
    /// パス無し起動(`befold --line-numbers` 等)は新規に開くウィンドウが無いため、
    /// 行番号/ソース表示/並び順のオーバーライドは開いている全ウィンドウへ直接適用する。
    func openPaths(_ paths: [String], options: CLIOpenOptions) {
        if let showHiddenFiles = options.showHiddenFiles {
            windowManager.setHiddenFiles(showHiddenFiles)
        }
        guard !paths.isEmpty else {
            windowManager.applyDisplayOverrides(
                showLineNumbers: options.showLineNumbers,
                sourceMode: options.sourceMode,
                sortOrder: options.sortOrder.map { _ in options.viewerSortOrder },
                showSidebar: options.showSidebar
            )
            return
        }
        for path in paths {
            openViewer(for: URL(fileURLWithPath: path), options: options)
        }
    }

    private func openViewer(for url: URL, options: CLIOpenOptions) {
        let isDirectory = DirectoryLister.isDirectory(url)
        guard let target = DirectoryLister.resolveFileToOpen(at: url) else {
            presentNoFileAlert()
            return
        }
        windowManager.openViewer(
            for: target, forceSidebarVisible: isDirectory,
            sidebarVisibleOverride: options.showSidebar,
            initialSortOrder: options.viewerSortOrder,
            showLineNumbersOverride: options.showLineNumbers,
            sourceModeOverride: options.sourceMode
        )
    }

    private func presentNoFileAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "cli.folder.noFile", bundle: .l10n)
        alert.runModal()
    }

    /// ファイル選択パネルを表示し、選択されたファイルをビューアで開く。
    /// 初期ディレクトリはキーウィンドウが表示中のファイルのディレクトリ、
    /// 無ければ（未オープン含む）ホームディレクトリを使う。
    @objc func showOpenPanel() {
        let controller = NSApp.keyWindow?.windowController as? ViewerWindowController
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.directoryURL = OpenPanelDirectoryResolver.resolve(
            currentFileDirectory: controller?.fileURL.deletingLastPathComponent(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.openViewer(for: url)
            }
        }
    }

    /// Help > befold Help。GitHub の README をブラウザで開く。
    @objc func openHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/YTommy109/befold#readme") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: aboutPanelOptions)
    }

    private var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return [.credits: AboutPanelCredits.make(font: font)]
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    /// メニューの「Install 'befold' command in PATH」。/usr/local/bin に CLI コマンドの symlink を設置する。
    @objc func installCLI(_ sender: Any?) {
        let installPath = CLIInstaller.defaultInstallPath
        let result = CLIInstaller.install(bundlePath: Bundle.main.bundlePath, installPath: installPath)
        switch result {
        case .success:
            CLIInstallUI.presentInstallSucceeded()
        case .failure:
            CLIInstallUI.presentInstallFailed()
        }
    }

    /// View > Show/Hide Hidden Files(⌘⌃H)。不可視ファイル表示を全ウィンドウで一括切替する。
    @objc func toggleHiddenFiles(_ sender: Any?) {
        windowManager.toggleHiddenFiles()
    }
}

// MARK: - SPUUpdaterDelegate

extension AppDelegate: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateChannel.read(from: .standard).feedURLString
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHiddenFiles(_:)) {
            menuItem.title = hiddenFilesPreference.showHiddenFiles
                ? String(localized: "menu.view.hideHiddenFiles", bundle: .l10n)
                : String(localized: "menu.view.showHiddenFiles", bundle: .l10n)
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
