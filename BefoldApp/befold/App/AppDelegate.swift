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
    }

    nonisolated static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch CLIArgumentParser.parse(arguments) {
        case .success(.help):
            print(CLIArgumentParser.usageText)
            exit(0)
        case let .success(.openPaths(paths, options)):
            launch(withInitialPaths: paths, options: options)
        case let .success(.subcommand(name, arguments)):
            runSubcommand(name: name, arguments: arguments)
        case let .failure(error):
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(64)
        }
    }

    /// GUI を起動せず、サブコマンドの結果を stdout/stderr へ出力してプロセスを終了する。
    private nonisolated static func runSubcommand(name: String, arguments: [String]) -> Never {
        let result = MainActor.assumeIsolated { () -> CLICommandResult in
            switch name {
            case "bookmark":
                CLIBookmarkCommand.run(arguments)
            case "check":
                CLICheckCommand.run(arguments)
            default:
                CLICommandResult(message: "未実装のサブコマンドです: \(name)", exitCode: 1)
            }
        }
        if result.exitCode == 0 {
            print(result.message)
        } else {
            FileHandle.standardError.write(Data((result.message + "\n").utf8))
        }
        exit(result.exitCode)
    }

    /// 既に起動中のインスタンスがあればそちらへ転送し、無ければ新規に GUI を起動する。
    private nonisolated static func launch(withInitialPaths paths: [String], options: CLIOpenOptions) {
        MainActor.assumeIsolated {
            if let running = CLIInstanceRouter.runningInstance() {
                if CLIInstanceRouter.forward(paths: paths, options: options, to: running) {
                    exit(0)
                }
                FileHandle.standardError.write(Data("既存インスタンスへの転送に失敗しました\n".utf8))
                exit(1)
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = AppDelegate(initialPaths: paths, initialOptions: options)
            app.delegate = delegate
            AppDelegate.shared = delegate
            app.run()
        }
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = DocumentController()
        sessionRestorer.captureSavedState()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCLIOpenRequest(_:)),
            name: CLIInstanceRouter.openRequestNotificationName, object: nil
        )
    }

    /// 別プロセスの CLI 起動から、起動中の当インスタンスへ転送されたオープン要求を処理する。
    @objc private func handleCLIOpenRequest(_ notification: Notification) {
        guard let (paths, options) = CLIInstanceRouter.decode(userInfo: notification.userInfo) else { return }
        if let requestID = CLIInstanceRouter.requestID(from: notification.userInfo) {
            CLIInstanceRouter.sendAck(requestID: requestID)
        }
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
            sessionRestorer.restoreLastSession()
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
    func openPaths(_ paths: [String], options: CLIOpenOptions) {
        if let showHiddenFiles = options.showHiddenFiles {
            windowManager.setHiddenFiles(showHiddenFiles)
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
            initialSortOrder: options.sortOrder == .alphabetical ? .alphabetical : .foldersFirst,
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
        let installPath = URL(fileURLWithPath: "/usr/local/bin/befold")
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
