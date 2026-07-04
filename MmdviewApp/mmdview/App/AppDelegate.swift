import AppKit
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate?
    private let sessionStore: SessionStore
    private let windowManager: ViewerWindowManager
    private let sessionRestorer: SessionRestorer
    private let updateCoordinator = UpdateCheckCoordinator()
    private lazy var recentDocumentsMenuController = RecentDocumentsMenuController { [weak self] url in
        self?.openViewer(for: url)
    }

    override init() {
        let sessionStore = SessionStore()
        let zoomStore = ZoomStore()
        let windowManager = ViewerWindowManager(sessionStore: sessionStore, zoomStore: zoomStore)
        self.sessionStore = sessionStore
        self.windowManager = windowManager
        sessionRestorer = SessionRestorer(sessionStore: sessionStore, windowManager: windowManager)
        super.init()
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
        sessionRestorer.captureSavedState()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            helpAction: #selector(openHelp(_:)),
            recentMenuDelegate: recentDocumentsMenuController
        )
        sessionRestorer.restoreLastSession()
        NSApp.activate()
        updateCoordinator.run(userInitiated: false)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateCoordinator.run(userInitiated: false)
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
    func openViewer(for url: URL) {
        windowManager.openViewer(for: url)
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

    /// Help > mmdview Help。GitHub の README をブラウザで開く。
    @objc func openHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/YTommy109/mmdview#readme") else { return }
        NSWorkspace.shared.open(url)
    }

    /// About パネルを表示し、あわせて更新を自動チェックする。
    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        updateCoordinator.run(userInitiated: false)
    }

    /// メニューの「Check for Updates…」。キャッシュを無視して確認し、結果を必ず表示する。
    @objc func checkForUpdates(_ sender: Any?) {
        updateCoordinator.run(userInitiated: true)
    }

    // MARK: - Supported Types

    /// オープンパネルで許可するファイル種別。
    /// 拡張子→UTI のバインディングは他アプリの宣言で変わる（.md が
    /// net.daringfireball.markdown ではなく com.unknown.md に解決される環境がある）ため、
    /// 拡張子からの解決結果と既知の UTI の両方を許可する。
    private static let supportedContentTypes: [UTType] = {
        let extensions = FileType.allExtensions
        let identifiers = [
            "com.degino.mmdview.mermaid-diagram",
            "net.daringfireball.markdown",
            "net.ia.markdown",
            "com.unknown.md",
        ]
        let resolved = extensions.compactMap { UTType(filenameExtension: $0) }
            + identifiers.compactMap { UTType($0) }
        var types: [UTType] = []
        for type in resolved where !types.contains(type) {
            types.append(type)
        }
        return types
    }()
}
