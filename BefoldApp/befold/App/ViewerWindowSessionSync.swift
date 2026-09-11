import BefoldKit
import Foundation

/// ウィンドウイベント(クローズ・rename・ファイル切替・キー化)を受けて、
/// コントローラ辞書のキー付け替えとセッション・履歴・ブックマークを追随させる。
///
/// `ViewerWindowManager` から切り出した独立の型。ウィンドウの生成と保持
/// (どの窓を開くか・どこに置くか)と、開閉に伴う記録の追随
/// (セッション・最近使った項目・ブックマーク)は別の関心で、後者はウィンドウを
/// 作らない。辞書の実体は引き続きマネージャが持ち、こちらは
/// `register` / `detach` を呼ぶだけ(書き換え口を増やさない)。
@MainActor
final class ViewerWindowSessionSync: ViewerWindowControllerDelegate {
    /// 辞書の付け替えと各ストアの所有者。マネージャがこの型を保持するため unowned。
    private unowned let manager: ViewerWindowManager

    init(manager: ViewerWindowManager) {
        self.manager = manager
    }

    /// url を表示しているウィンドウが 1 つも残っていなければ、セッション記録から閉じたことにする。
    ///
    /// 同一ファイルを複数ウィンドウで開くことを許している(controllers は 1 対多)ため、
    /// 閉じる/切り替えるたびに無条件で noteClosed を呼ぶと、まだ表示している窓が残っていても
    /// セッション集合とアクティブ記録から消える(TASK-412)。参照が残っているかの判定は
    /// controllers の有無そのもので足りるので、SessionStore 側に参照カウントは持たせない。
    /// close 経路と remap 経路が別々の判定を持たないよう、必ずここを通す。
    ///
    /// **スライド窓は数に入れない**(TASK-612)。復元の対象外(`isRestorable == false`)なので、
    /// 通常窓を閉じてスライド窓だけが残った状態は「復元するものが無い」= 閉じたことにする。
    /// 逆にスライド窓を閉じても、通常窓が残っていれば記録は消さない。
    private func noteClosedIfNoWindowRemains(for url: URL) {
        let remaining = manager.controllers[url.normalizedPathKey] ?? []
        guard !remaining.contains(where: \.kind.isRestorable) else { return }
        manager.sessionStore.noteClosed(url)
    }

    /// 「開いた」記録の唯一の入口(TASK-612)。セッション(`isRestorable`)と利用履歴
    /// (`recordsUsageHistory`。判定は `RecentDocumentsStore` が持つ)は別の述語で決まるが、
    /// どちらも窓の種別から決まるので、呼び出し側が片方だけ書けない形にする。
    /// 新規オープン(`openViewer`)とファイル切替(`remapController`)がここを通る。
    func noteOpened(_ url: URL, in controller: ViewerWindowController) {
        if controller.kind.isRestorable {
            manager.sessionStore.noteOpened(url)
        }
        manager.recentDocumentsStore.noteOpened(url, kind: controller.kind)
    }

    /// rename / switch に伴うウィンドウ管理辞書のキー付け替えとセッション・履歴の更新。
    private func remapController(
        _ controller: ViewerWindowController,
        from oldURL: URL,
        to newURL: URL,
        isRename: Bool
    ) {
        manager.detach(controller, fromKey: oldURL.normalizedPathKey)
        manager.register(controller, forKey: newURL.normalizedPathKey)
        if isRename, controller.kind.isRestorable {
            manager.sessionStore.noteRenamed(from: oldURL, to: newURL)
        }
        noteClosedIfNoWindowRemains(for: oldURL)
        if isRename {
            if controller.kind.isRestorable {
                manager.sessionStore.noteOpened(newURL)
            }
            manager.recentDocumentsStore.noteRenamed(
                from: oldURL, to: newURL, kind: controller.kind
            )
            manager.shared.bookmarkStore.noteRenamed(from: oldURL, to: newURL)
        } else {
            noteOpened(newURL, in: controller)
        }
    }

    // MARK: - ViewerWindowControllerDelegate

    func viewerWindowWillClose(_ controller: ViewerWindowController) {
        manager.recentRepositories.recordTabGroup(of: controller)
        manager.detach(controller, fromKey: controller.fileURL.normalizedPathKey)
        noteClosedIfNoWindowRemains(for: controller.fileURL)
    }

    func viewerWindow(_ controller: ViewerWindowController, didAdjustFrameTo descriptor: String) {
        manager.windowFrame.recordUserAdjustedFrame(descriptor, for: controller.kind)
    }

    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController) {
        // スライド窓をアクティブ記録にすると、復元時にキーにする窓の指定が存在しないパスを指す。
        if controller.kind.isRestorable {
            manager.sessionStore.noteActivated(controller.fileURL)
        }
        // タブグループが壊れていない状態を観測できる唯一の契機。ここで記録しておかないと、
        // タブを複数開いたウィンドウの構成は close 時には既に失われている。
        manager.recentRepositories.recordTabGroup(of: controller)
        // タブ選択の変更は必ずそのタブがキーになる契機を伴うため、Window メニューの
        // 一覧の揃え直しもここへ相乗りさせる(タブ選択専用の通知は AppKit に無い)。
        manager.syncWindowsMenuMembership()
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

    func viewerWindowDidToggleDiffLayout(_ controller: ViewerWindowController) {
        manager.display.refreshAllToolbars()
    }
}
