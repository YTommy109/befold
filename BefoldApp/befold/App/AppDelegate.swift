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
    let windowManager: ViewerWindowManager
    private let hiddenFilesPreference: HiddenFilesPreference
    let codeFontPreference: CodeFontPreference
    private let sessionRestorer: SessionRestorer
    /// 単一インスタンスのパネルウィンドウ(About・設定・Help 配下)。初回のトグルで生成し、
    /// 以降は同じインスタンスを使い回す。
    var hostedPanels: [HostedPanel: HostedPanelWindowController] = [:]
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private let recentDocumentsStore: RecentDocumentsStore
    private let bookmarkStore: BookmarkStore
    private let recentRepositoriesStore: RecentRepositoriesStore
    /// 「最近使ったリポジトリ」メニューの階層化に使う worktree 一覧キャッシュ。
    /// git 呼び出しは起動時と新規リポジトリ記録時の非同期解決だけで、メニュー構築では読むだけ。
    private let worktreeCatalog: WorktreeCatalog
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
    private lazy var recentRepositoriesMenuController = RecentRepositoriesMenuController(
        entries: { [weak self] in self?.recentRepositoriesStore.entries() ?? [] },
        worktrees: { [weak self] root in self?.worktreeCatalog.worktrees(forMainRoot: root) ?? [] },
        openHandler: { [weak self] entry in
            self?.sessionRestorer.openRepository(root: entry.root, savedTabGroup: entry.lastTabGroup)
        },
        clearHandler: { [weak self] in self?.recentRepositoriesStore.clear() }
    )
    private lazy var quickOpenPanelController = QuickOpenPanelController(
        makeEnvironment: { [weak self] in self?.makeQuickOpenEnvironment() },
        onOpen: { [weak self] url in self?.openFromQuickOpen(url) }
    )

    override init() {
        let sessionStore = SessionStore()
        let recentDocumentsStore = RecentDocumentsStore()
        let bookmarkStore = BookmarkStore(defaults: .standard)
        let recentRepositoriesStore = RecentRepositoriesStore()
        let hiddenFilesPreference = HiddenFilesPreference()
        let findOptionsPreference = FindOptionsPreference()
        let codeFontPreference = CodeFontPreference()
        let perFileState = PerFileStateStore()
        let worktreeCatalog = WorktreeCatalog()
        let windowManager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference,
            codeFontPreference: codeFontPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            recentRepositoriesStore: recentRepositoriesStore,
            // リポジトリを記録したら、その本体ルートの worktree 一覧も裏で解決し直しておく。
            // 次にメニューを開いた時点でキャッシュに載っていれば階層表示になる。
            onRepositoryRecorded: { mainRoot in
                Task { await worktreeCatalog.refresh(mainRoots: [mainRoot]) }
            }
        )
        self.worktreeCatalog = worktreeCatalog
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.bookmarkStore = bookmarkStore
        self.recentRepositoriesStore = recentRepositoriesStore
        self.windowManager = windowManager
        self.hiddenFilesPreference = hiddenFilesPreference
        self.codeFontPreference = codeFontPreference
        sessionRestorer = SessionRestorer(sessionStore: sessionStore, windowManager: windowManager)
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCLIOpenRequest(_:)),
            name: CLIRequestWire.requestNotificationName, object: nil
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

    /// 別プロセスの CLI 起動から、起動中の当インスタンスへ転送された要求を処理する。
    /// forward() は ACK 未受信時に同じ requestID で再送するため、ACK は受信のたびに返すが、
    /// 要求の実行は requestID ごとに一度だけに絞る。
    ///
    /// ブックマーク追加を CLI プロセスではなくここで行うことで、UserDefaults の
    /// ブックマーク配列を書くプロセスを GUI に一本化し、CLI との同時更新で
    /// 片方の追加が消える競合を防ぐ(CLIRequestForwarder 参照)。
    @objc private func handleCLIOpenRequest(_ notification: Notification) {
        guard let request = CLIRequestWire.decode(userInfo: notification.userInfo) else { return }
        let requestID = CLIRequestWire.requestID(from: notification.userInfo)
        if let requestID {
            CLIRequestWire.sendAck(requestID: requestID)
        }
        guard cliRequestDeduplicator.shouldProcess(requestID: requestID) else { return }
        switch request {
        case let .open(paths, options):
            openPaths(paths, options: options)
            NSApp.activate()
        case let .bookmark(paths):
            // ユーザーは GUI を見ていないので前面化はしない。
            windowManager.addBookmarks(for: paths.map { URL(fileURLWithPath: $0) })
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        recentDocumentsStore.seedIfNeeded(with: NSDocumentController.shared.recentDocumentURLs)
        let mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            helpActions: MainMenuHelpActions(
                visitWebsite: #selector(openHelp(_:)),
                featureOverview: #selector(showFeatureOverview(_:)),
                keyboardShortcuts: #selector(showKeyboardShortcuts(_:)),
                aiIntegration: #selector(showAIIntegration(_:)),
                ossAcknowledgements: #selector(showOSSLicenses(_:))
            ),
            recentMenuDelegate: recentDocumentsMenuController,
            bookmarksMenuDelegate: bookmarksMenuController,
            recentRepositoriesMenuDelegate: recentRepositoriesMenuController
        )
        // AppKit は mainMenu に設定した後、Close All や Start Dictation などの項目を
        // 勝手に差し込む。Help のショートカット一覧には自前で定義したものだけを載せたいので、
        // 設定する前のメニューから抽出しておく。
        MenuShortcutCatalog.snapshot = MenuShortcutCatalog.groups(from: mainMenu, appMenuTitle: "befold")
        NSApp.mainMenu = mainMenu
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
        // 「最近使ったリポジトリ」メニューは保存済みリストをそのまま表示するため、
        // 存在しなくなった worktree 等の整理は起動時にここで1回だけ非同期に行う。
        // 併せて、残ったエントリの本体ルートごとに worktree 一覧を解決してキャッシュへ載せる
        // (メニュー表示時には git を呼ばず、このキャッシュを読むだけにするため)。
        Task { [recentRepositoriesStore, worktreeCatalog] in
            await recentRepositoriesStore.pruneMissingAsync()
            let mainRootPaths = Set(recentRepositoriesStore.entries().map { $0.mainRootPath ?? $0.rootPath })
            await worktreeCatalog.refresh(mainRoots: mainRootPaths.map { URL(fileURLWithPath: $0) })
        }
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
        // App Translocation 下では bundlePath がランダム化された一時マウントを指すため、
        // 正しく設置済みの symlink でも参照先不一致(staleSymlink)に見えてしまう。
        // ここで案内しても再インストールは translocatedBundle で断られるだけなので黙る。
        guard !CLIInstaller.isTranslocated(bundlePath: bundlePath) else { return }
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
        // 解決は非同期のため、渡された順にウィンドウが出るよう 1 本の Task で逐次に開く。
        Task {
            for url in urls {
                await openViewer(for: url, options: CLIOpenOptions())
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// いま操作対象になっているビューアウィンドウのコントローラ。
    /// Quick Open パネル(NSPanel, canBecomeMain=false)がキーを奪っている間も
    /// NSApp.mainWindow は元のビューアウィンドウを指し続けるため、パネル表示中でも
    /// 正しい元ウィンドウを引ける。元ウィンドウが閉じられていれば残存ウィンドウを返す。
    private var activeViewerController: ViewerWindowController? {
        NSApp.mainWindow?.windowController as? ViewerWindowController
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let controller = activeViewerController {
            sessionStore.noteActivated(controller.fileURL)
        }
        // 終了時は windowWillClose が発火しないことがあるため、リポジトリ単位のタブ構成も
        // セッション全体のレイアウトと同じタイミングでスナップショットしておく。
        windowManager.recordAllRecentRepositoryTabGroups()
        sessionStore.saveLayout(sessionRestorer.currentSessionLayout())
        sessionStore.freeze()
        return .terminateNow
    }

    // MARK: - Actions

    /// 指定 URL のファイルをビューアウィンドウで開く(DocumentController・Recent メニューからも呼ばれる)。
    /// ディレクトリが渡された場合は、フォルダー内最初のファイルを開く(CLI シム経由の想定)。
    /// 拡張子を問わずウィンドウは開かれ、未対応の内容ならビューア側でプレースホルダー表示する。
    func openViewer(for url: URL) {
        Task { await openViewer(for: url, options: CLIOpenOptions()) }
    }

    /// 参照クリック由来のオープン。disposition/relativeTo をそのまま ViewerWindowManager へ通す。
    func openViewer(for url: URL, disposition: OpenDisposition, relativeTo sourceWindow: NSWindow?) {
        Task {
            await openViewer(
                for: url, options: CLIOpenOptions(),
                disposition: disposition, relativeTo: sourceWindow
            )
        }
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
            windowManager.applyDisplayOverrides(options)
            return
        }
        // 同上。解決を待つ間に順序が入れ替わらないよう、1 本の Task 内で逐次に開く。
        Task {
            for path in paths {
                await openViewer(for: URL(fileURLWithPath: path), options: options)
            }
        }
    }

    /// ディレクトリ判定とオープン対象の解決は実 FS の存在確認・列挙を伴い、ネットワーク
    /// ボリューム上ではウィンドウを出す前に停止しうる。解決だけメインアクターの外へ逃がし、
    /// ウィンドウ生成は戻ってから行う。
    private func openViewer(
        for url: URL, options: CLIOpenOptions,
        disposition: OpenDisposition = .currentTab, relativeTo sourceWindow: NSWindow? = nil
    ) async {
        let resolved = await Task.detached {
            (isDirectory: DirectoryLister.isDirectory(url), target: DirectoryLister.resolveFileToOpen(at: url))
        }.value
        let isDirectory = resolved.isDirectory
        guard let target = resolved.target else {
            presentNoFileAlert()
            return
        }
        windowManager.openViewer(
            for: target, options: options, disposition: disposition, relativeTo: sourceWindow,
            forceSidebarVisible: isDirectory
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
        let controller = activeViewerController
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
        updaterController.checkForUpdates(sender)
    }

    /// メニューの「Install 'befold' command in PATH」。/usr/local/bin に CLI コマンドの symlink を設置する。
    ///
    /// 書き込みは管理者認証(AppleScript の `with administrator privileges`)へフォールバックしうる。
    /// 認証ダイアログはユーザーがパスワードを入力し終えるまで戻らないため、メインアクターで待つと
    /// その間 CLI 転送の ACK 応答まで止まる。設置処理そのものをメインアクター外へ逃がし、
    /// 結果の案内だけを戻ってから出す(NSAppleScript の生成・実行はどちらも同じ detached タスク内で
    /// 完結するため、単一スレッドからの利用という前提は保たれる)。
    @objc func installCLI(_ sender: Any?) {
        let installPath = CLIInstaller.defaultInstallPath
        let bundlePath = Bundle.main.bundlePath
        Task {
            let result = await Task.detached {
                CLIInstaller.install(bundlePath: bundlePath, installPath: installPath)
            }.value
            presentInstallResult(result)
        }
    }

    private func presentInstallResult(_ result: Result<Void, CLIInstallError>) {
        switch result {
        case .success:
            CLIInstallUI.presentInstallSucceeded()
        case .failure(.translocatedBundle):
            // 書き込み権限の問題ではないため、再試行を促す汎用の失敗案内では解決に導けない。
            CLIInstallUI.presentInstallBlockedByTranslocation()
        case .failure(.writeFailed):
            CLIInstallUI.presentInstallFailed()
        }
    }

    /// View > Show/Hide Hidden Files(⌘⌃H)。不可視ファイル表示を全ウィンドウで一括切替する。
    @objc func toggleHiddenFiles(_ sender: Any?) {
        windowManager.toggleHiddenFiles()
    }

    /// App > Settings…(⌘,)。単一インスタンスで、
    /// 最前面なら閉じ、そうでなければ開く/前面化するトグル動作にする。
    @objc func showSettings(_ sender: Any?) {
        togglePanel(.settings)
    }

    /// File > Quick Open(⌘P)。パス入力と fuzzy 検索のパネルを開く。
    @objc func showQuickOpen(_ sender: Any?) {
        quickOpenPanelController.toggle()
    }

    /// パネルを開いた時点のアプリ状態から候補源を組み立てる。
    /// 索引はウィンドウと共有し、パネルを開くたびに `git ls-files` をやり直さない。
    private func makeQuickOpenEnvironment() -> AppQuickOpenEnvironment {
        // パネルは canBecomeMain=false のため、表示中でも mainWindow は元のビューアの
        // まま。専用の状態を持たず activeViewerController から都度引く。
        let currentFileURL = activeViewerController?.fileURL
        if let currentFileURL {
            windowManager.gitFileIndex.warm(forFileAt: currentFileURL)
        }
        return AppQuickOpenEnvironment(
            gitIndex: windowManager.gitFileIndex,
            recentDocumentsStore: recentDocumentsStore,
            bookmarkStore: bookmarkStore,
            hiddenFilesPreference: hiddenFilesPreference,
            currentFileURL: currentFileURL
        )
    }

    /// Quick Open の決定先を開く。決定時点で操作対象のビューアウィンドウがあればそこで
    /// 切り替え、無ければ(全ウィンドウを閉じた場合など)新規ウィンドウを開く。
    /// 決定経路(onOpen)はパネルを畳んでから呼ばれるため、mainWindow は残存ビューアを指す。
    private func openFromQuickOpen(_ url: URL) {
        guard let controller = activeViewerController else {
            openViewer(for: url)
            return
        }
        controller.focusWindow()
        controller.switchFile(to: url)
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
