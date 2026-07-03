import AppKit
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate?
    private var windowControllers: [String: ViewerWindowController] = [:]
    private let sessionStore = SessionStore()
    private let zoomStore = ZoomStore()
    /// 前回セッションで開いていたファイル。起動イベントで開かれるファイルの記録と混ざらないよう
    /// applicationWillFinishLaunching で読み取り、applicationDidFinishLaunching で復元する。
    private var urlsToRestore: [URL] = []
    private let updateChecker = UpdateChecker()
    private let updateFlow = UpdateFlowController()
    /// 自動チェックで通知済みの最新バージョン(セッション中の再通知を抑止する)。
    private var announcedVersion: String?
    private lazy var recentDocumentsMenuController = RecentDocumentsMenuController { [weak self] url in
        self?.openViewer(for: url)
    }

    nonisolated static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = AppDelegate()
            app.delegate = delegate
            AppDelegate.shared = delegate
            app.run()
        }
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = DocumentController()
        urlsToRestore = sessionStore.savedURLs()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            recentMenuDelegate: recentDocumentsMenuController
        )
        restoreLastSession()
        NSApp.activate()
        runUpdateCheck(userInitiated: false)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        runUpdateCheck(userInitiated: false)
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
        // 終了処理中のウィンドウクローズで復元リストが空にならないよう記録を止める
        sessionStore.freeze()
        return .terminateNow
    }

    // MARK: - Window Management

    /// 前回セッションで開いていたファイルを再オープンする。存在しなくなったファイルは記録からも取り除く。
    private func restoreLastSession() {
        for url in urlsToRestore {
            if FileManager.default.fileExists(atPath: url.path) {
                openViewer(for: url)
            } else {
                sessionStore.noteClosed(url)
            }
        }
        urlsToRestore = []
    }

    /// 指定 URL のファイルをビューアウィンドウで開く。
    /// 同じファイルが既に開かれている場合は既存ウィンドウを前面に表示する。
    func openViewer(for url: URL) {
        let key = url.normalizedPathKey
        if let existing = windowControllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ViewerWindowController(fileURL: url, zoomStore: zoomStore)
        windowControllers[key] = controller
        controller.onClose = { [weak self] in
            self?.windowControllers.removeValue(forKey: key)
            self?.sessionStore.noteClosed(url)
        }
        controller.showWindow(nil)
        sessionStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// ファイル選択パネルを表示し、選択されたファイルをビューアで開く。
    @objc func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedContentTypes
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.openViewer(for: url)
            }
        }
    }

    // MARK: - Update Check

    /// About パネルを表示し、あわせて更新を自動チェックする。
    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        runUpdateCheck(userInitiated: false)
    }

    /// メニューの「Check for Updates…」。キャッシュを無視して確認し、結果を必ず表示する。
    @objc func checkForUpdates(_ sender: Any?) {
        runUpdateCheck(userInitiated: true)
    }

    /// 更新チェックを実行し、表示ポリシーに従って結果を提示する。
    /// 自動チェックは更新ありのときのみ、かつ同一バージョンはセッション中 1 回だけ表示する。
    private func runUpdateCheck(userInitiated: Bool) {
        Task {
            guard !updateFlow.isRunning else { return }
            let result = await updateChecker.check(bypassCache: userInitiated)
            switch result {
            case let .updateAvailable(current, latest, downloadURL):
                if !userInitiated, latest == announcedVersion { return }
                announcedVersion = latest
                await updateFlow.run(current: current, latest: latest, downloadURL: downloadURL)
            case let .upToDate(current):
                if userInitiated { UpdateUI.presentUpToDate(current: current) }
            case .failed:
                if userInitiated { UpdateUI.presentCheckFailed() }
            }
        }
    }

    // MARK: - Supported Types

    private static let supportedContentTypes: [UTType] = {
        var types: [UTType] = []
        if let mmd = UTType(filenameExtension: "mmd") { types.append(mmd) }
        if let mermaid = UTType(filenameExtension: "mermaid") { types.append(mermaid) }
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }()
}
