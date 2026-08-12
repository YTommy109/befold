import AppKit
import BefoldKit

/// タブグループの組み立てと、ウィンドウの Space 復帰。
/// 「複数の NSWindow を 1 つのまとまりとして扱う」規則をここ 1 箇所に置き、
/// セッション保存・復元と「最近使ったリポジトリ」が同じ解釈を共有する。
extension ViewerWindowManager {
    /// window を baseWindow のタブグループへ結合する。タブ結合の手続きはここが単一の実装元で、
    /// セッション復元(SessionRestorer.restoreTabGroup)も同じ経路を通る。
    /// baseWindow が nil のときは何もしない = 独立したウィンドウのままにする
    /// (「開けない」より「タブにならない」へ縮退させる)。
    /// - Parameter select: 結合したタブを選択状態にするか。復元時は元の選択タブを別途決めるため false。
    func attachAsTab(_ window: NSWindow, to baseWindow: NSWindow?, select: Bool) {
        guard let baseWindow, baseWindow !== window else { return }
        baseWindow.addTabbedWindow(window, ordered: .above)
        if select {
            window.tabGroup?.selectedWindow = window
        }
    }

    /// window が属するタブグループのウィンドウ群。タブ化されていなければ自身のみ。
    /// タブ構成のスナップショットを取る側(セッション保存・最近使ったリポジトリ)が
    /// 同じ解釈を共有するための単一の入口。
    static func tabWindows(of window: NSWindow) -> [NSWindow] {
        window.tabGroup?.windows ?? [window]
    }

    /// タブ構成スナップショットの組み立て本体(NSWindow に依存しない純粋関数)。
    /// 「終了時レイアウト」と「最近使ったリポジトリのタブ構成」は同じ形式で相互に
    /// 保存・復元されるため、組み立て規則はここ 1 箇所だけに置く。
    /// ビューアパスを 1 つも持たなければ nil(ビューアウィンドウでない・全タブが閉じた等)。
    static func makeTabGroup<Window>(
        tabWindows: [Window], selectedWindow: Window, viewerPath: (Window) -> String?
    ) -> SessionLayout.TabGroup? {
        let paths = tabWindows.compactMap(viewerPath)
        guard !paths.isEmpty else { return nil }
        return SessionLayout.TabGroup(paths: paths, selectedPath: viewerPath(selectedWindow))
    }

    /// window(自身のタブグループ)を SessionLayout.TabGroup として組み立てる。
    /// タブが1枚も無ければ nil(ビューアウィンドウでない・既に全タブが閉じた等)。
    func tabGroup(of window: NSWindow) -> SessionLayout.TabGroup? {
        Self.makeTabGroup(
            tabWindows: Self.tabWindows(of: window),
            selectedWindow: window.tabGroup?.selectedWindow ?? window,
            viewerPath: viewerPath(of:)
        )
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
        for controller in allControllers {
            guard let window = controller.window,
                  Self.isDetachedFromSpace(
                      isVisible: window.isVisible, isOnActiveSpace: window.isOnActiveSpace
                  )
            else { continue }
            window.orderFront(nil)
        }
    }
}
