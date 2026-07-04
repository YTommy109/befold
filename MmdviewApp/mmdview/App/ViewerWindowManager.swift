import AppKit

/// ビューアウィンドウの生成・管理(正規化パス → コントローラ辞書)と、
/// ウィンドウイベント(クローズ・rename・キー化)に伴うセッション記録の更新を担う。
@MainActor
final class ViewerWindowManager {
    private(set) var controllers: [String: ViewerWindowController] = [:]
    private let sessionStore: SessionStore
    private let zoomStore: ZoomStore

    init(sessionStore: SessionStore, zoomStore: ZoomStore) {
        self.sessionStore = sessionStore
        self.zoomStore = zoomStore
    }

    /// 指定 URL のファイルをビューアウィンドウで開く。
    /// 同じファイルが既に開かれている場合は既存ウィンドウを前面に表示する。
    func openViewer(for url: URL) {
        let key = url.normalizedPathKey
        if let existing = controllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ViewerWindowController(fileURL: url, zoomStore: zoomStore)
        controllers[key] = controller
        bindCallbacks(for: controller, key: key, url: url)
        controller.showWindow(nil)
        sessionStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
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
        controller.onRename = { [weak self, weak controller] oldURL, newURL in
            guard let self, let controller else { return }
            let oldKey = oldURL.normalizedPathKey
            let newKey = newURL.normalizedPathKey
            if controllers[oldKey] === controller {
                controllers.removeValue(forKey: oldKey)
            }
            controllers[newKey] = controller
            sessionStore.noteRenamed(from: oldURL, to: newURL)
            sessionStore.noteClosed(oldURL)
            sessionStore.noteOpened(newURL)
            NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
            bindCallbacks(for: controller, key: newKey, url: newURL)
        }
    }
}
