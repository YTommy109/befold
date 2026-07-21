import AppKit
import BefoldKit
import Sparkle

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
    /// CLI 経由の起動時に指定された初期オープン対象パス。GUI ダブルクリック起動時は空。
    private let initialPaths: [String]
    /// CLI から指定された表示オプション(未指定項目は nil で、既存の保存済み設定・既定値を維持する)。
    private let initialOptions: CLIOpenOptions
    /// CLIInstanceRouter.forward() の再送による同一requestIDの二重処理を防ぐ。
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

    init(initialPaths: [String] = [], initialOptions: CLIOpenOptions = CLIOpenOptions()) {
        self.initialPaths = initialPaths
        self.initialOptions = initialOptions
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
        // NSApplication.run() 開始(≒applicationWillFinishLaunching発火)を待たずに登録する。
        // このインスタンスは launch() の .launchAsNewInstance 分岐でのみ生成され、生成された時点で
        // 既に NSRunningApplication 経由で「起動中インスタンス」として他プロセスから見えうるため、
        // observer 登録を先送りするほど後続 CLI 起動からの forward() が誰にも受信されないレース窓が
        // 広がる(task-85)。DistributedNotificationCenter への登録自体はランループの起動を必要としない。
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCLIOpenRequest(_:)),
            name: CLIInstanceRouter.openRequestNotificationName, object: nil
        )
    }

    nonisolated static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            var command = try BefoldRootCommand.parseAsRoot(arguments)
            try command.run()
        } catch {
            BefoldRootCommand.exit(withError: error)
        }
    }

    /// `launch(withInitialPaths:options:)` が転送結果を受けて取るべき行動。
    /// 実際の `exit()`/`NSApplication.run()` を呼ばずに分岐だけをテストできるよう切り出す。
    enum LaunchAction: Equatable {
        /// 転送に成功した。この起動はここで終了する。
        case exitSuccess
        /// 転送に失敗し、かつ復元すべき対象パスも無い(パス無し起動)ため、
        /// 旧実装と同じく自身のセッションを復元してウィンドウを開く(task-78)。
        case launchAsNewInstance
        /// 対象パスがある転送が失敗した。ユーザーへエラーを伝えて終了する。
        case exitWithForwardError
    }

    /// 既存インスタンスの有無・転送結果・パスの有無から、取るべき行動を決定する。
    /// 副作用(exit/NSApplication.run)を持たないため単体テスト可能。
    nonisolated static func decideLaunchAction(
        paths: [String], runningInstance: NSRunningApplication?, forwardSucceeded: Bool
    ) -> LaunchAction {
        guard runningInstance != nil else { return .launchAsNewInstance }
        if forwardSucceeded { return .exitSuccess }
        return paths.isEmpty ? .launchAsNewInstance : .exitWithForwardError
    }

    /// paths も表示オプションも指定されていない、単なる `befold` 起動(既存インスタンスの
    /// 前面化だけが目的)かどうか。この場合は転送すべき内容が無いため、
    /// forward() の ACK 待ちコスト(task-88 参照)を経由せず直接 activate() すれば十分(task-89)。
    nonisolated static func isTrivialActivateOnly(paths: [String], options: CLIOpenOptions) -> Bool {
        paths.isEmpty && options == CLIOpenOptions()
    }

    /// 既に起動中のインスタンスがあればそちらへ転送し、無ければ新規に GUI を起動する。
    /// `BefoldRootCommand.run()` から呼ばれる(パス解析・サブコマンド分岐は ArgumentParser に委譲する)。
    nonisolated static func launch(withInitialPaths paths: [String], options: CLIOpenOptions) {
        MainActor.assumeIsolated {
            let running = CLIInstanceRouter.runningInstance()
            if let running, isTrivialActivateOnly(paths: paths, options: options) {
                running.activate()
                exit(0)
            }
            let forwardSucceeded = running.map {
                CLIInstanceRouter.forward(paths: paths, options: options, to: $0)
            } ?? false

            switch decideLaunchAction(paths: paths, runningInstance: running, forwardSucceeded: forwardSucceeded) {
            case .exitSuccess:
                exit(0)
            case .exitWithForwardError:
                FileHandle.standardError.write(Data("既存インスタンスへの転送に失敗しました\n".utf8))
                exit(1)
            case .launchAsNewInstance:
                let app = NSApplication.shared
                app.setActivationPolicy(.regular)
                let delegate = AppDelegate(initialPaths: paths, initialOptions: options)
                app.delegate = delegate
                AppDelegate.shared = delegate
                app.run()
            }
        }
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = DocumentController()
        sessionRestorer.captureSavedState()
    }

    /// 別プロセスの CLI 起動から、起動中の当インスタンスへ転送されたオープン要求を処理する。
    /// forward() は ACK 未受信時に同じ requestID で再送するため、ACK は受信のたびに返すが、
    /// openPaths の実行は requestID ごとに一度だけに絞る(task-79)。
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
        // 初回のみシステム管理の Recent Documents を取り込む(以降はアプリ側の記録が正)
        recentDocumentsStore.seedIfNeeded(with: NSDocumentController.shared.recentDocumentURLs)
        NSApp.mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            helpAction: #selector(openHelp(_:)),
            recentMenuDelegate: recentDocumentsMenuController,
            bookmarksMenuDelegate: bookmarksMenuController
        )
        if initialPaths.isEmpty {
            sessionRestorer.restoreLastSession(options: initialOptions)
        } else {
            openPaths(initialPaths, options: initialOptions)
        }
        NSApp.activate()
        // アップデータによる再起動直後は、復元したウィンドウが WindowServer の遷移状態により
        // どの Space にも属さず不可視になることがあるため、少し待ってから載せ直す
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [windowManager] in
            windowManager.rescueWindowsDetachedFromSpace()
        }
        #if DEBUG
            updaterController.updater.automaticallyChecksForUpdates = false
        #endif
        updaterController.startUpdater()
        // startUpdater() は前回チェックから updateCheckInterval 経過時のみチェックするため、
        // 起動毎に必ずチェックさせるには明示的な呼び出しが必要
        if updaterController.updater.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
        notifyIfCLIShimIsStale()
    }

    /// 起動時に一度だけ /usr/local/bin/befold の状態を読み取り専用でチェックし、
    /// 古い実体ファイル/参照先不一致の symlink が残っている場合のみ再インストールを案内する。
    /// 書き込み(再インストール自体)は行わない。
    private func notifyIfCLIShimIsStale() {
        let status = CLIShimInspector.status(
            bundlePath: Bundle.main.bundlePath,
            installPath: CLIInstaller.defaultInstallPath
        )
        switch status {
        case .legacyFile, .staleSymlink:
            CLIInstallUI.presentReinstallRecommended()
        case .notInstalled, .upToDate:
            break
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
        // ウィンドウが閉じられる前に、現在のタブ構成とアクティブファイルを確定値で保存する
        if let keyWindow = NSApp.keyWindow,
           let controller = keyWindow.windowController as? ViewerWindowController
        {
            sessionStore.noteActivated(controller.fileURL)
        }
        sessionStore.saveLayout(sessionRestorer.currentSessionLayout())
        // 終了処理中のウィンドウクローズで復元リストが空にならないよう記録を止める
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
    /// 行番号/ソース表示/並び順のオーバーライドは開いている全ウィンドウへ直接適用する(task-82)。
    func openPaths(_ paths: [String], options: CLIOpenOptions) {
        if let showHiddenFiles = options.showHiddenFiles {
            windowManager.setHiddenFiles(showHiddenFiles)
        }
        guard !paths.isEmpty else {
            windowManager.applyDisplayOverrides(
                showLineNumbers: options.showLineNumbers,
                sourceMode: options.sourceMode,
                sortOrder: options.sortOrder.map { _ in options.viewerSortOrder }
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

    /// メニューの「Install 'befold' command in PATH」。/usr/local/bin にシムスクリプトを設置する。
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
