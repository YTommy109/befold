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

    func openViewer(for url: URL) {
        openViewer(for: url, options: CLIOpenOptions())
    }

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
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
