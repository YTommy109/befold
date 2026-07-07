import AppKit

/// ビューアウィンドウの生成・管理(正規化パス → コントローラ辞書)と、
/// ウィンドウイベント(クローズ・rename・キー化)に伴うセッション記録の更新を担う。
@MainActor
final class ViewerWindowManager {
    private(set) var controllers: [String: ViewerWindowController] = [:]
    private let sessionStore: SessionStore
    private let zoomStore: ZoomStore
    private let recentDocumentsStore: RecentDocumentsStore

    init(sessionStore: SessionStore, zoomStore: ZoomStore, recentDocumentsStore: RecentDocumentsStore) {
        self.sessionStore = sessionStore
        self.zoomStore = zoomStore
        self.recentDocumentsStore = recentDocumentsStore
    }

    /// 指定 URL のファイルをビューアウィンドウで開く。
    /// 同じファイルが既に開かれている場合は既存ウィンドウを前面に表示する。
    func openViewer(for url: URL, forceSidebarVisible: Bool = false) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 経路によりシンボリックリンクの解決状態が異なる(/tmp と /private/tmp 等)ため、
            // 表示パスは normalizedPathKey と同じ正規化で揃える
            showFileNotFoundAlert(path: url.normalizedPathKey)
            return
        }

        let key = url.normalizedPathKey
        if let existing = controllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ViewerWindowController(
            fileURL: url,
            zoomStore: zoomStore,
            forceSidebarVisible: forceSidebarVisible
        )
        controllers[key] = controller
        bindCallbacks(for: controller, key: key, url: url)
        controller.showWindow(nil)
        sessionStore.noteOpened(url)
        recentDocumentsStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// まだウィンドウが無い状態(新規オープン時)にファイルが見つからないことを通知する。
    /// ウィンドウ内シート表示の ViewerWindowController.showFileNotFoundAlert とは異なり、
    /// この時点では親となるウィンドウが存在しないため runModal で表示する。
    private func showFileNotFoundAlert(path: String) {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "alert.fileNotFound.message",
            defaultValue: "File Not Found",
            bundle: .l10n
        )
        alert.informativeText = path
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
            if let controller, controllers[key] === controller {
                controllers.removeValue(forKey: key)
            }
            sessionStore.noteClosed(url)
        }
        controller.isFileOpenInAnotherWindow = { [weak self, weak controller] targetURL in
            guard let self, let controller else { return false }
            return isOpenInAnotherWindow(targetURL, excluding: controller)
        }
        controller.focusWindowForFile = { [weak self, weak controller] targetURL in
            guard let self, let controller else { return }
            focusExistingWindow(targetURL, excluding: controller)
        }
        controller.onRename = { [weak self, weak controller] oldURL, newURL in
            guard let self, let controller else { return }
            remapController(controller, from: oldURL, to: newURL, isRename: true)
        }
        controller.onSwitchFile = { [weak self, weak controller] oldURL, newURL in
            guard let self, let controller else { return }
            remapController(controller, from: oldURL, to: newURL, isRename: false)
        }
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
    /// 差分は「リネームか(レイアウトの付け替え・履歴の旧パス除去)、単なる切替か
    /// (履歴は新規オープン扱い)」のみで、それ以外の付け替え手順は共通。
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
        bindCallbacks(for: controller, key: newKey, url: newURL)
    }
}
