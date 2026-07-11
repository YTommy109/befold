import AppKit

/// ビューアウィンドウの生成・管理(正規化パス → コントローラ辞書)と、
/// ウィンドウイベント(クローズ・rename・キー化)に伴うセッション記録の更新を担う。
@MainActor
final class ViewerWindowManager {
    private(set) var controllers: [String: ViewerWindowController] = [:]
    private let sessionStore: SessionStore
    private let zoomStore: ZoomStore
    private let recentDocumentsStore: RecentDocumentsStore
    private let hiddenFilesPreference: HiddenFilesPreference
    private let findOptionsPreference: FindOptionsPreference
    private let sourceModeStore: SourceModeStore
    private let scrollPositionStore: ScrollPositionStore

    /// - Parameter hiddenFilesPreference: 本番では必ず AppDelegate が持つ単一の共有インスタンスを渡すこと。
    ///   デフォルト値は、不可視ファイル挙動に無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    /// - Parameter sourceModeStore: 同上。ソース表示モード挙動に無関心なテストが省略できるようにする。
    /// - Parameter scrollPositionStore: 同上。スクロール位置挙動に無関心なテストが省略できるようにする。
    init(
        sessionStore: SessionStore, zoomStore: ZoomStore, recentDocumentsStore: RecentDocumentsStore,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        sourceModeStore: SourceModeStore = SourceModeStore(),
        scrollPositionStore: ScrollPositionStore = ScrollPositionStore()
    ) {
        self.sessionStore = sessionStore
        self.zoomStore = zoomStore
        self.recentDocumentsStore = recentDocumentsStore
        self.hiddenFilesPreference = hiddenFilesPreference
        self.findOptionsPreference = findOptionsPreference
        self.sourceModeStore = sourceModeStore
        self.scrollPositionStore = scrollPositionStore
    }

    /// 不可視ファイル表示のON/OFFを反転し、開いている全ウィンドウのサイドバーへ即座に反映する。
    func toggleHiddenFiles() {
        hiddenFilesPreference.showHiddenFiles.toggle()
        refreshAllSidebars()
    }

    /// 開いている全ウィンドウのサイドバー(ファイル一覧)を再読み込みする。
    private func refreshAllSidebars() {
        for controller in controllers.values {
            controller.sidebar.refreshFileList()
        }
    }

    /// 指定 URL のファイルをビューアウィンドウで開く。
    /// 同じファイルが既に開かれている場合は既存ウィンドウを前面に表示する。
    func openViewer(for url: URL, forceSidebarVisible: Bool = false) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 新規オープン時点ではまだ親ウィンドウが無いため over: nil でモーダル表示する。
            FileNotFoundUI.present(url: url, over: nil)
            return
        }

        let key = url.normalizedPathKey
        if let existing = controllers[key] {
            NSApp.activate()
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ViewerWindowController(
            fileURL: url,
            zoomStore: zoomStore,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference,
            sourceModeStore: sourceModeStore,
            scrollPositionStore: scrollPositionStore,
            forceSidebarVisible: forceSidebarVisible
        )
        controllers[key] = controller
        controller.delegate = self
        NSApp.activate()
        controller.showWindow(nil)
        sessionStore.noteOpened(url)
        recentDocumentsStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// ウィンドウが「表示中のはずなのにアクティブ Space に居ない」状態かを判定する。
    static func isDetachedFromSpace(isVisible: Bool, isOnActiveSpace: Bool) -> Bool {
        isVisible && !isOnActiveSpace
    }

    /// Space に載れなかった可視ウィンドウを現在の Space に載せ直す。
    /// アップデータによる再起動では、旧プロセス終了直後の WindowServer 遷移状態で
    /// 復元ウィンドウがどの Space にも属さず不可視になることがある(再 orderFront で復旧する)。
    /// 起動直後にのみ呼ぶこと(ユーザーが他 Space に移した後のウィンドウに触れないように)。
    func rescueWindowsDetachedFromSpace() {
        for controller in controllers.values {
            guard let window = controller.window,
                  Self.isDetachedFromSpace(
                      isVisible: window.isVisible, isOnActiveSpace: window.isOnActiveSpace
                  )
            else { continue }
            window.orderFront(nil)
        }
    }

    /// 指定の正規化パスに対応する開状態のウィンドウを返す。
    func window(forPath path: String) -> NSWindow? {
        controllers[path]?.window
    }

    /// ビューアウィンドウなら対応するファイルの正規化パスを返す。
    func viewerPath(of window: NSWindow) -> String? {
        (window.windowController as? ViewerWindowController)?.fileURL.normalizedPathKey
    }

    /// targetURL が controller 以外のウィンドウで既に開かれているかを判定する純粋チェック。
    private func isOpenInAnotherWindow(
        _ targetURL: URL, excluding controller: ViewerWindowController
    ) -> Bool {
        let key = targetURL.normalizedPathKey
        guard let existing = controllers[key], existing !== controller else { return false }
        return true
    }

    /// targetURL を開いている別ウィンドウを前面化する。
    private func focusExistingWindow(
        _ targetURL: URL, excluding controller: ViewerWindowController
    ) {
        let key = targetURL.normalizedPathKey
        guard let existing = controllers[key], existing !== controller else { return }
        existing.window?.makeKeyAndOrderFront(nil)
    }

    /// rename / switch に伴うウィンドウ管理辞書のキー付け替えとセッション・履歴の更新。
    private func remapController(
        _ controller: ViewerWindowController,
        from oldURL: URL,
        to newURL: URL,
        isRename: Bool
    ) {
        let oldKey = oldURL.normalizedPathKey
        let newKey = newURL.normalizedPathKey
        if controllers[oldKey] === controller {
            controllers.removeValue(forKey: oldKey)
        }
        controllers[newKey] = controller
        if isRename {
            sessionStore.noteRenamed(from: oldURL, to: newURL)
        }
        sessionStore.noteClosed(oldURL)
        sessionStore.noteOpened(newURL)
        if isRename {
            recentDocumentsStore.noteRenamed(from: oldURL, to: newURL)
        } else {
            recentDocumentsStore.noteOpened(newURL)
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
    }
}

// MARK: - ViewerWindowControllerDelegate

extension ViewerWindowManager: ViewerWindowControllerDelegate {
    func viewerWindowWillClose(_ controller: ViewerWindowController) {
        let key = controller.fileURL.normalizedPathKey
        if controllers[key] === controller {
            controllers.removeValue(forKey: key)
        }
        sessionStore.noteClosed(controller.fileURL)
    }

    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController) {
        sessionStore.noteActivated(controller.fileURL)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL
    ) {
        remapController(controller, from: oldURL, to: newURL, isRename: true)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    ) {
        remapController(controller, from: oldURL, to: newURL, isRename: false)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, isFileOpenInAnotherWindow url: URL
    ) -> Bool {
        isOpenInAnotherWindow(url, excluding: controller)
    }

    func viewerWindow(_ controller: ViewerWindowController, focusWindowForFile url: URL) {
        focusExistingWindow(url, excluding: controller)
    }

    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController) {
        toggleHiddenFiles()
    }
}
