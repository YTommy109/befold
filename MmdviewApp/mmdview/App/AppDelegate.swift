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
    /// 前回終了時のタブ構成。urlsToRestore と同様に applicationWillFinishLaunching で先読みする。
    private var layoutToRestore: SessionLayout?
    /// 前回アクティブだったファイルの正規化パス。
    private var activePathToRestore: String?
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
        layoutToRestore = sessionStore.savedLayout()
        activePathToRestore = sessionStore.savedActivePath()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            helpAction: #selector(openHelp(_:)),
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
        // ウィンドウが閉じられる前に、現在のタブ構成とアクティブファイルを確定値で保存する
        if let keyWindow = NSApp.keyWindow,
           let controller = keyWindow.windowController as? ViewerWindowController
        {
            sessionStore.noteActivated(controller.fileURL)
        }
        sessionStore.saveLayout(currentSessionLayout())
        // 終了処理中のウィンドウクローズで復元リストが空にならないよう記録を止める
        sessionStore.freeze()
        return .terminateNow
    }

    // MARK: - Window Management

    /// 現在のウィンドウ/タブ構成をスナップショットする。
    /// NSApp.orderedWindows は前面から順に返るため、グループの並びも前面優先で保存される。
    private func currentSessionLayout() -> SessionLayout {
        var groups: [SessionLayout.TabGroup] = []
        var seenWindows: Set<ObjectIdentifier> = []

        func appendGroup(for window: NSWindow) {
            guard !seenWindows.contains(ObjectIdentifier(window)),
                  viewerPath(of: window) != nil else { return }

            let tabWindows = window.tabGroup?.windows ?? [window]
            for tabWindow in tabWindows {
                seenWindows.insert(ObjectIdentifier(tabWindow))
            }

            let paths = tabWindows.compactMap { viewerPath(of: $0) }
            guard !paths.isEmpty else { return }
            let selectedWindow = window.tabGroup?.selectedWindow ?? window
            groups.append(SessionLayout.TabGroup(paths: paths, selectedPath: viewerPath(of: selectedWindow)))
        }

        for window in NSApp.orderedWindows {
            appendGroup(for: window)
        }
        // orderedWindows は最小化(Dock 収納)・非表示のウィンドウを含まないため、
        // NSApp.windows で残りのビューアウィンドウのグループを末尾に補完する
        for window in NSApp.windows {
            appendGroup(for: window)
        }
        return SessionLayout(groups: groups)
    }

    /// ビューアウィンドウなら対応するファイルの正規化パスを返す。
    private func viewerPath(of window: NSWindow) -> String? {
        (window.windowController as? ViewerWindowController)?.fileURL.normalizedPathKey
    }

    /// 前回セッションで開いていたファイルを再オープンする。存在しなくなったファイルは記録からも取り除く。
    /// SessionLayout があればタブグループ構成・タブ順・選択タブを再現し、無ければ従来どおり開いた順に開く。
    /// 最後に前回アクティブだったファイルをキーウィンドウにする。
    private func restoreLastSession() {
        // 復元中のウィンドウ表示がシステムの「タブ優先」設定で勝手にタブ結合しないよう、
        // 自動タブ化を一時的に無効にする(グループ構成は addTabbedWindow で明示的に再現する)
        let allowsTabbing = NSWindow.allowsAutomaticWindowTabbing
        NSWindow.allowsAutomaticWindowTabbing = false
        defer { NSWindow.allowsAutomaticWindowTabbing = allowsTabbing }

        let existingURLs = urlsToRestore.filter { url in
            if FileManager.default.fileExists(atPath: url.path) { return true }
            sessionStore.noteClosed(url)
            return false
        }
        urlsToRestore = []

        let urlByPath = Dictionary(existingURLs.map { ($0.normalizedPathKey, $0) }) { first, _ in first }
        var restoredPaths: Set<String> = []

        if let layout = layoutToRestore?.filtered(to: Set(urlByPath.keys)) {
            for group in layout.groups {
                restoreTabGroup(group, urlByPath: urlByPath)
                restoredPaths.formUnion(group.paths)
            }
        }
        layoutToRestore = nil

        // レイアウトに無いファイル(クラッシュ後に開いたもの等)は従来どおり開いた順に開く
        for url in existingURLs where !restoredPaths.contains(url.normalizedPathKey) {
            openViewer(for: url)
        }

        // 前回アクティブだったファイルをキーウィンドウにする(開けていなければ成り行きのまま)
        if let activePath = activePathToRestore,
           let window = windowControllers[activePath]?.window
        {
            window.makeKeyAndOrderFront(nil)
        }
        activePathToRestore = nil
    }

    /// 1 つのタブグループを復元する。先頭のウィンドウに残りを順にタブ連結し、選択タブを再現する。
    private func restoreTabGroup(_ group: SessionLayout.TabGroup, urlByPath: [String: URL]) {
        var previousWindow: NSWindow?
        for path in group.paths {
            guard let url = urlByPath[path] else { continue }
            openViewer(for: url)
            guard let window = windowControllers[path]?.window else { continue }
            // システムの「書類を開くときはタブで開く」設定に依存しないよう明示的にタブ化する
            previousWindow?.addTabbedWindow(window, ordered: .above)
            previousWindow = window
        }
        if let selectedPath = group.selectedPath,
           let selectedWindow = windowControllers[selectedPath]?.window
        {
            selectedWindow.tabGroup?.selectedWindow = selectedWindow
        }
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
        bindCallbacks(for: controller, key: key, url: url)
        controller.showWindow(nil)
        sessionStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// ウィンドウ管理辞書のキー付け替えとセッション記録更新のため、
    /// コントローラの onClose / onRename を現在の key / url で束ね直す。
    /// rename 時は新しい key / url で再束縛し、onClose が古い値を捕捉し続けないようにする。
    private func bindCallbacks(for controller: ViewerWindowController, key: String, url: URL) {
        controller.onBecomeKey = { [weak self, weak controller] in
            guard let self, let controller else { return }
            // fileURL は rename で書き換わるため、クロージャ引数の url ではなく現在値を参照する
            sessionStore.noteActivated(controller.fileURL)
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self else { return }
            // 付け替え後に別コントローラが同じキーを使っている可能性を避け、
            // 自分が登録されている場合のみ除去する
            if let controller, windowControllers[key] === controller {
                windowControllers.removeValue(forKey: key)
            }
            sessionStore.noteClosed(url)
        }
        controller.onRename = { [weak self, weak controller] oldURL, newURL in
            guard let self, let controller else { return }
            let oldKey = oldURL.normalizedPathKey
            let newKey = newURL.normalizedPathKey
            if windowControllers[oldKey] === controller {
                windowControllers.removeValue(forKey: oldKey)
            }
            windowControllers[newKey] = controller
            sessionStore.noteRenamed(from: oldURL, to: newURL)
            sessionStore.noteClosed(oldURL)
            sessionStore.noteOpened(newURL)
            NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
            bindCallbacks(for: controller, key: newKey, url: newURL)
        }
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

    // MARK: - Help

    /// Help > mmdview Help。GitHub の README をブラウザで開く。
    @objc func openHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/YTommy109/mmdview#readme") else { return }
        NSWorkspace.shared.open(url)
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
