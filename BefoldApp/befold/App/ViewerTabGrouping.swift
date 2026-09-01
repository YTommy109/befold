import AppKit
import BefoldKit

/// タブグループの規則。「複数の NSWindow を 1 つのまとまりとして扱う」解釈を
/// ここ 1 箇所に置き、セッション保存・復元と「最近使ったリポジトリ」が同じ規則を共有する。
///
/// 知っているのは AppKit のタブグループ、`SessionLayout.TabGroup` の組み立て形式、
/// 「ビューアウィンドウかどうか」の判定だけ。開いているウィンドウの管理台帳
/// (`ViewerWindowManager.controllers`) も共有ストアも知らないため、状態を持たない
/// enum にしてある(対象は必ず引数で受ける)。
@MainActor
enum ViewerTabGrouping {
    /// window を baseWindow のタブグループへ結合する。タブ結合の手続きはここが単一の実装元で、
    /// セッション復元(SessionRestorer.restoreTabGroup)も新規オープンも同じ経路を通る。
    /// baseWindow が nil のときは何もしない = 独立したウィンドウのままにする
    /// (「開けない」より「タブにならない」へ縮退させる)。
    /// - Parameter select: 結合したタブを選択状態にするか。復元時は元の選択タブを別途決めるため false。
    static func attachAsTab(_ window: NSWindow, to baseWindow: NSWindow?, select: Bool) {
        guard let baseWindow, baseWindow !== window else { return }
        baseWindow.addTabbedWindow(window, ordered: .above)
        if select {
            selectTab(window)
        }
    }

    /// window を表示する。baseWindow があれば **タブ結合してから** `show` を呼ぶ。
    /// この順序をここへ閉じ込めるのは、先に独立ウィンドウとして表示してからタブグループへ
    /// 吸収すると、AppKit の再親付けで「独立ウィンドウが出る → 畳まれてタブになる」中間状態が
    /// 1 フレーム見えるため(TASK-529)。表示を呼び出し側の `show` に預けることで、
    /// 順序を守っているかどうかをテストから観測できる。
    /// window が nil のときは結合をあきらめ `show` だけを呼ぶ
    /// (attachAsTab と同じ「開けないよりタブにならない」への縮退)。
    static func present(_ window: NSWindow?, asTabOf baseWindow: NSWindow?, select: Bool, show: () -> Void) {
        if let window {
            attachAsTab(window, to: baseWindow, select: select)
        }
        show()
    }

    /// window をそのタブグループの選択タブにする。タブ化されていなければ何もしない。
    /// 前面化(makeKeyAndOrderFront)に任せず明示的に選択するのは、タブ結合直後や
    /// ヘッドレス環境ではタブ選択が追随しないことがあるため。
    static func selectTab(_ window: NSWindow) {
        window.tabGroup?.selectedWindow = window
    }

    /// window を Window メニューから隠すべきか。タブグループの選択タブ以外を隠す判定で、
    /// `selectedTabOfGroup` が nil(タブ化されていない)なら隠さない。
    /// NSWindow に依存しない純粋関数にしてあるのは、判定だけをテストから固定するため。
    static func isExcludedFromWindowsMenu<Window: AnyObject>(
        _ window: Window, selectedTabOfGroup: Window?
    ) -> Bool {
        guard let selectedTabOfGroup else { return false }
        return selectedTabOfGroup !== window
    }

    /// Window メニューの一覧を「各ウィンドウの選択中タブだけ」に揃える。
    ///
    /// `NSApp.windowsMenu` へ載る一覧は AppKit が NSWindow 単位で自動生成するため、
    /// タブは 1 枚ずつ別項目として並ぶ。このメニューの用途はウィンドウの切り替えなので、
    /// 背面タブまで並ぶと目的の窓を選びにくい(TASK-531)。表示中でないタブを
    /// `isExcludedFromWindowsMenu` で外し、選択タブだけを残す。
    ///
    /// 対象はビューアウィンドウに限る(呼び出し側が渡す)。パネル類まで一括で
    /// false に戻すと、本来メニューへ載らないウィンドウを載せてしまうため。
    static func syncWindowsMenuMembership(among windows: [NSWindow]) {
        for window in windows {
            let excluded = isExcludedFromWindowsMenu(
                window, selectedTabOfGroup: window.tabGroup?.selectedWindow
            )
            if window.isExcludedFromWindowsMenu != excluded {
                window.isExcludedFromWindowsMenu = excluded
            }
        }
    }

    /// window が属するタブグループのウィンドウ群。タブ化されていなければ自身のみ。
    /// タブ構成のスナップショットを取る側(セッション保存・最近使ったリポジトリ)が
    /// 同じ解釈を共有するための単一の入口。
    static func tabWindows(of window: NSWindow) -> [NSWindow] {
        window.tabGroup?.windows ?? [window]
    }

    /// ビューアウィンドウなら対応するファイルの正規化パスを返す。
    /// ウィンドウ 1 枚だけを見て決まる判定なので、管理台帳を引かずに答えられる。
    static func viewerPath(of window: NSWindow) -> String? {
        (window.windowController as? ViewerWindowController)?.fileURL.normalizedPathKey
    }

    /// タブ構成スナップショットの組み立て本体(NSWindow に依存しない純粋関数)。
    /// 「終了時レイアウト」と「最近使ったリポジトリのタブ構成」は同じ形式で相互に
    /// 保存・復元されるため、組み立て規則はここ 1 箇所だけに置く。
    /// ビューアパスを 1 つも持たなければ nil(ビューアウィンドウでない・全タブが閉じた等)。
    static func makeTabGroup<Window>(
        tabWindows: [Window], selectedWindow: Window, viewerPath: (Window) -> String?,
        frame: String? = nil
    ) -> SessionLayout.TabGroup? {
        let paths = tabWindows.compactMap(viewerPath)
        guard !paths.isEmpty else { return nil }
        return SessionLayout.TabGroup(
            paths: paths, selectedPath: viewerPath(selectedWindow), frame: frame
        )
    }

    /// window(自身のタブグループ)を SessionLayout.TabGroup として組み立てる。
    /// タブが1枚も無ければ nil(ビューアウィンドウでない・既に全タブが閉じた等)。
    static func tabGroup(of window: NSWindow) -> SessionLayout.TabGroup? {
        makeTabGroup(
            tabWindows: tabWindows(of: window),
            selectedWindow: window.tabGroup?.selectedWindow ?? window,
            viewerPath: viewerPath(of:),
            frame: restorableFrameDescriptor(of: window)
        )
    }

    /// 復元に使える寸法。フルスクリーン中の値は通常ウィンドウの寸法として無意味なので
    /// 記録しない(`ViewerWindowController.windowDidEndLiveResize` と同じ判定)。
    static func restorableFrameDescriptor(of window: NSWindow) -> String? {
        window.styleMask.contains(.fullScreen) ? nil : window.frameDescriptor
    }

    /// ウィンドウが「表示中のはずなのにアクティブ Space に居ない」状態かを判定する。
    static func isDetachedFromSpace(isVisible: Bool, isOnActiveSpace: Bool) -> Bool {
        isVisible && !isOnActiveSpace
    }

    /// Space に載れなかった可視ウィンドウを現在の Space に載せ直す。
    /// アップデータによる再起動では、旧プロセス終了直後の WindowServer 遷移状態で
    /// 復元ウィンドウがどの Space にも属さず不可視になることがある(再 orderFront で復旧する)。
    /// 起動直後にのみ呼ぶこと(ユーザーが他 Space に移した後のウィンドウに触れないように)。
    static func rescueWindowsDetachedFromSpace(among windows: [NSWindow]) {
        for window in windows {
            guard isDetachedFromSpace(
                isVisible: window.isVisible, isOnActiveSpace: window.isOnActiveSpace
            )
            else { continue }
            window.orderFront(nil)
        }
    }
}
