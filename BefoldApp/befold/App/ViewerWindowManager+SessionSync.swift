import AppKit
import BefoldKit

/// ウィンドウイベント(クローズ・rename・ファイル切替・キー化)に伴う
/// コントローラ辞書のキー付け替えと、セッション・履歴・ブックマークの追随。
extension ViewerWindowManager {
    /// 指定の正規化パスに対応する開状態のウィンドウを返す。
    /// 同一ファイルを複数ウィンドウで開いている場合は、そのいずれか(先頭)を返す。
    func window(forPath path: String) -> NSWindow? {
        controllers[path]?.first?.window
    }

    /// url を表示しているウィンドウが 1 つも残っていなければ、セッション記録から閉じたことにする。
    ///
    /// 同一ファイルを複数ウィンドウで開くことを許している(controllers は 1 対多)ため、
    /// 閉じる/切り替えるたびに無条件で noteClosed を呼ぶと、まだ表示している窓が残っていても
    /// セッション集合とアクティブ記録から消える(TASK-412)。参照が残っているかの判定は
    /// controllers の有無そのもので足りるので、SessionStore 側に参照カウントは持たせない。
    /// close 経路と remap 経路が別々の判定を持たないよう、必ずここを通す。
    private func noteClosedIfNoWindowRemains(for url: URL) {
        guard controllers[url.normalizedPathKey] == nil else { return }
        sessionStore.noteClosed(url)
    }

    /// rename / switch に伴うウィンドウ管理辞書のキー付け替えとセッション・履歴の更新。
    private func remapController(
        _ controller: ViewerWindowController,
        from oldURL: URL,
        to newURL: URL,
        isRename: Bool
    ) {
        detach(controller, fromKey: oldURL.normalizedPathKey)
        register(controller, forKey: newURL.normalizedPathKey)
        if isRename {
            sessionStore.noteRenamed(from: oldURL, to: newURL)
        }
        noteClosedIfNoWindowRemains(for: oldURL)
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
        recentRepositories.recordTabGroup(of: controller)
        detach(controller, fromKey: controller.fileURL.normalizedPathKey)
        noteClosedIfNoWindowRemains(for: controller.fileURL)
    }

    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController) {
        sessionStore.noteActivated(controller.fileURL)
        // タブグループが壊れていない状態を観測できる唯一の契機。ここで記録しておかないと、
        // タブを複数開いたウィンドウの構成は close 時には既に失われている。
        recentRepositories.recordTabGroup(of: controller)
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

    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController) {
        display.toggleHiddenFiles()
    }

    func viewerWindowDidToggleChangedFilesOnly(_ controller: ViewerWindowController) {
        display.toggleChangedFilesOnly()
    }

    func viewerWindowDidToggleSidebarTreeLayout(_ controller: ViewerWindowController) {
        display.toggleSidebarLayoutMode()
    }

    func viewerWindowDidToggleDiffLayout(_ controller: ViewerWindowController) {
        display.refreshAllToolbars()
    }
}
