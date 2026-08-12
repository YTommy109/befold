import AppKit
import BefoldKit

/// アプリ全体で 1 つの表示設定を、開いている全ウィンドウへ配る一括反映。
///
/// ここに置くのは「設定の実体はアプリに 1 つで、窓は表示を追随させるだけ」のものに限る。
/// 窓ごとのライブ値(表示モード・拡大率など、ADR 0002)は窓側の責務であり、
/// ここから配ってはならない。
extension ViewerWindowManager {
    /// 不可視ファイル表示のON/OFFを反転し、開いている全ウィンドウのサイドバーへ即座に反映する。
    func toggleHiddenFiles() {
        sidebarDisplayPreference.showHiddenFiles.toggle()
        refreshAllSidebars()
    }

    /// git 変更ファイルのみ表示のON/OFFを反転し、開いている全ウィンドウへ即座に反映する。
    /// git 状態は取り直すが、一覧の再列挙は行わない。
    func toggleChangedFilesOnly() {
        sidebarDisplayPreference.showChangedFilesOnly.toggle()
        allControllers.forEach { $0.sidebar.applyChangedFilesOnlyToggle() }
    }

    /// サイドバーの表示モード(ドリルダウン / ツリー展開)を反転し、開いている全ウィンドウへ
    /// 即座に反映する。表示モードは行配列そのものを変えるため、各ウィンドウで行を組み直す
    /// 必要がある。ツリーからドリルダウンへ戻すときは展開状態も捨てる
    /// (捨てないと、モードを戻したのに展開したままの行が残る)。
    func toggleSidebarLayoutMode() {
        let next: SidebarLayoutMode =
            sidebarDisplayPreference.layoutMode == .tree ? .drillDown : .tree
        sidebarDisplayPreference.layoutMode = next
        if next == .drillDown {
            allControllers.forEach { $0.sidebar.discardExpansion() }
        }
        // 行の組み直しは refreshFileList の経路へ合流させる。rebuildRows を直接叩くと
        // 「ルートの一覧が届く前に行を組み直さない」不変条件を迂回することになる。
        refreshAllSidebars()
    }

    /// CLI の `--hidden-files`/`--no-hidden-files` から呼ばれる。値を直接設定し、
    /// 開いている全ウィンドウのサイドバーへ即座に反映する。
    func setHiddenFiles(_ value: Bool) {
        guard sidebarDisplayPreference.showHiddenFiles != value else { return }
        sidebarDisplayPreference.showHiddenFiles = value
        refreshAllSidebars()
    }

    /// 開いている全ウィンドウのサイドバー(ファイル一覧)を再読み込みする。
    /// 呼んでよいのはこの型と その extension だけ(表示設定を変えた直後の再同期用)。
    func refreshAllSidebars() {
        for controller in allControllers {
            controller.sidebar.refreshFileList()
        }
    }

    /// CLI の `--bookmark <path>` から転送された追加を適用し、開いている全ウィンドウの
    /// ツールバーへ即座に反映する。書き込みを GUI プロセスへ一本化する意図で
    /// AppDelegate から呼ばれる(CLIRequestForwarder 参照)。
    /// ブックマーク状態はツールバーが表示のたびに store から読み直すため、
    /// 反映は全ウィンドウの再同期で足り、変更通知の購読機構は要らない。
    func addBookmarks(for urls: [URL]) {
        for url in urls {
            bookmarkStore.add(url)
        }
        refreshAllToolbars()
    }

    /// 開いている全ウィンドウのツールバーを現在状態へ再同期する。
    /// 呼んでよいのはこの型と その extension だけ(共有設定を変えた直後の再同期用)。
    func refreshAllToolbars() {
        for controller in allControllers {
            controller.refreshToolbarState()
        }
    }

    /// codeFontPreference の現在値を、開いている全ウィンドウの WebView へ即座に反映する。
    /// フォント設定変更(環境設定 UI 等)から呼ばれる。
    func applyCodeFontToAllWindows() {
        for controller in allControllers {
            controller.applyCodeFontFromPreference()
        }
    }
}
