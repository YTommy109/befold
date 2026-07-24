import AppKit
import BefoldKit

/// ビューアウィンドウの生成・管理(正規化パス → コントローラ辞書)と、
/// ウィンドウイベント(クローズ・rename・キー化)に伴うセッション記録の更新を担う。
@MainActor
final class ViewerWindowManager {
    private(set) var controllers: [String: ViewerWindowController] = [:]
    private let sessionStore: SessionStore
    private let recentDocumentsStore: RecentDocumentsStore
    private let hiddenFilesPreference: HiddenFilesPreference
    private let findOptionsPreference: FindOptionsPreference
    private let perFileState: PerFileStateStore
    private let bookmarkStore: BookmarkStore

    /// - Parameter hiddenFilesPreference: 本番では必ず AppDelegate が持つ単一の共有インスタンスを渡すこと。
    ///   デフォルト値は、不可視ファイル挙動に無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    /// - Parameter perFileState: 同上。ファイル毎の永続表示状態(倍率・ソース表示モード・
    ///   スクロール位置)の束。これらの挙動に無関心なテストが省略できるようにする。
    /// - Parameter bookmarkStore: 同上。ブックマーク挙動に無関心なテストが省略できるようにする。
    init(
        sessionStore: SessionStore, recentDocumentsStore: RecentDocumentsStore,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        perFileState: PerFileStateStore = PerFileStateStore(),
        bookmarkStore: BookmarkStore = BookmarkStore()
    ) {
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.hiddenFilesPreference = hiddenFilesPreference
        self.findOptionsPreference = findOptionsPreference
        self.perFileState = perFileState
        self.bookmarkStore = bookmarkStore
    }

    /// 不可視ファイル表示のON/OFFを反転し、開いている全ウィンドウのサイドバーへ即座に反映する。
    func toggleHiddenFiles() {
        hiddenFilesPreference.showHiddenFiles.toggle()
        refreshAllSidebars()
    }

    /// CLI の `--hidden-files`/`--no-hidden-files` から呼ばれる。値を直接設定し、
    /// 開いている全ウィンドウのサイドバーへ即座に反映する。
    func setHiddenFiles(_ value: Bool) {
        guard hiddenFilesPreference.showHiddenFiles != value else { return }
        hiddenFilesPreference.showHiddenFiles = value
        refreshAllSidebars()
    }

    /// 開いている全ウィンドウのサイドバー(ファイル一覧)を再読み込みする。
    private func refreshAllSidebars() {
        for controller in controllers.values {
            controller.sidebar.refreshFileList()
        }
    }

    /// パス無し CLI 起動(`befold --line-numbers` 等)から、開いている全ウィンドウへ表示オプションを適用する。
    /// 新規ウィンドウ生成時は initialSortOrder/showLineNumbersOverride/sourceModeOverride で
    /// 個別に適用できるが、パス無し起動では開くべき新規ウィンドウが無いため、既存の全ウィンドウへ
    /// 直接反映する(task-82)。隠しファイル表示は setHiddenFiles が別途アプリ全体へ反映するため対象外。
    func applyDisplayOverrides(
        showLineNumbers: Bool?, sourceMode: Bool?, sortOrder: SortOrder?, showSidebar: Bool?
    ) {
        for controller in controllers.values {
            if let showLineNumbers { controller.store.applyShowLineNumbersOverride(showLineNumbers) }
            if let sourceMode { controller.setSourceMode(sourceMode) }
            if let sortOrder {
                controller.fileListModel.sortOrder = sortOrder
                controller.sidebar.refreshFileList()
            }
            if let showSidebar { controller.setSidebarCollapsed(!showSidebar) }
        }
    }

    /// 指定 URL のファイルをビューアウィンドウで開く。
    /// 同じファイルが既に開かれている場合は既存ウィンドウを前面に表示する。
    func openViewer(
        for url: URL, forceSidebarVisible: Bool = false,
        sidebarVisibleOverride: Bool? = nil,
        initialSortOrder: SortOrder = .foldersFirst,
        showLineNumbersOverride: Bool? = nil,
        sourceModeOverride: Bool? = nil
    ) {
        guard DirectoryLister.fileExists(url) else {
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

        let lastActivePathKey = sessionStore.savedActivePath()
        // 開閉の解決順: CLI の明示指定(--sidebar/--no-sidebar) > フォルダーオープンによる強制表示 > 記憶の引き継ぎ。
        let initialSidebarCollapsed: Bool = if let sidebarVisibleOverride {
            !sidebarVisibleOverride
        } else if forceSidebarVisible {
            false
        } else {
            perFileState.sidebar.initialCollapsed(for: url, lastActivePathKey: lastActivePathKey)
        }
        perFileState.sidebar.setCollapsed(initialSidebarCollapsed, for: url)

        let initialFrameDescriptor = perFileState.windowFrame.initialFrameDescriptor(
            for: url, lastActivePathKey: lastActivePathKey
        )
        if let initialFrameDescriptor {
            perFileState.windowFrame.setFrameDescriptor(initialFrameDescriptor, for: url)
        }

        let controller = ViewerWindowController(
            fileURL: url,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            initialSidebarCollapsed: initialSidebarCollapsed,
            initialFrameDescriptor: initialFrameDescriptor,
            initialSortOrder: initialSortOrder,
            showLineNumbersOverride: showLineNumbersOverride,
            sourceModeOverride: sourceModeOverride,
            openFileInNewWindow: { [weak self] fileURL in self?.openViewer(for: fileURL) }
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

    /// targetURL を controller 以外のウィンドウで開いている ViewerWindowController を返す。
    private func existingOtherController(
        for targetURL: URL, excluding controller: ViewerWindowController
    ) -> ViewerWindowController? {
        let key = targetURL.normalizedPathKey
        guard let existing = controllers[key], existing !== controller else { return nil }
        return existing
    }

    /// targetURL が controller 以外のウィンドウで既に開かれているかを判定する純粋チェック。
    private func isOpenInAnotherWindow(
        _ targetURL: URL, excluding controller: ViewerWindowController
    ) -> Bool {
        existingOtherController(for: targetURL, excluding: controller) != nil
    }

    /// targetURL を開いている別ウィンドウを前面化する。
    private func focusExistingWindow(
        _ targetURL: URL, excluding controller: ViewerWindowController
    ) {
        existingOtherController(for: targetURL, excluding: controller)?.window?.makeKeyAndOrderFront(nil)
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
            bookmarkStore.noteRenamed(from: oldURL, to: newURL)
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
