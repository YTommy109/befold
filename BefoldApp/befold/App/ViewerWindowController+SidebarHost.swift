import Foundation

// MARK: - SidebarNavigatorHost

/// `SidebarNavigator` がウィンドウ側へ問い合わせる口(現在ファイル・履歴状態の変化・
/// git 状態の反映)と、`ViewerWindowManager` から全ウィンドウへ一斉に流す再同期の口。
///
/// どちらも「外から来た契機を、このウィンドウの担当者へ配る」だけの薄い層に保つ。
/// 判断や状態はここに置かない。
@MainActor
extension ViewerWindowController: SidebarNavigatorHost {
    /// SidebarNavigator が現在ファイルを都度参照するための橋渡し。
    var currentFileURL: URL {
        fileURL
    }

    /// 履歴状態の変化をツールバーへ反映する。
    func historyStateDidChange() {
        refreshToolbarState()
    }

    /// git バッジが更新されたら、同じ契機で表示中ファイルの差分も取り直す。
    /// 差分側だけを別の契機で呼ばないこと(保存・`.git/index` 変更・キーウィンドウ化・
    /// 絞り込みトグルのどれかが片方にしか届かなくなる / TASK-330)。
    func gitStatusDidApply() {
        diffPresenter.refresh()
    }

    /// 現在の表示状態をツールバーの全アイテムへ再同期する。
    /// ウィンドウ内部の状態変更に加え、CLI からの表示オプション上書き
    /// (ViewerWindowManager.applyDisplayOverrides)のような外部要因からも呼ばれる。
    func refreshToolbarState() {
        toolbarController.refreshToolbarState()
    }

    /// 現在の codeFontPreference の値を WebView へ注入し直して即時反映する。
    /// フォント設定変更時に ViewerWindowManager.applyCodeFontToAllWindows から呼ばれる。
    func applyCodeFontFromPreference() {
        webViewCommands.applyCodeFont(
            family: codeFontPreference.fontFamily, points: codeFontPreference.fontSizePoints
        )
    }
}
