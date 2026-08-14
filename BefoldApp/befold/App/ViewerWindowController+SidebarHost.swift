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

    /// サイドバーの git 文脈(バッジの元になる git 状態、基準ディレクトリの解決結果)が
    /// 変わったときの唯一の受け口。
    ///
    /// 差分の取り直しとツールバーの再同期を**同じ契機に束ねる**。差分側だけを別の契機で
    /// 呼ぶと、保存・`.git/index` 変更・キーウィンドウ化・絞り込みトグルのどれかが
    /// 片方にしか届かなくなる(TASK-330)。ツールバーを同じ口へ足したのは、差分表示モードの
    /// 選択可否が git の事実から導かれるようになったため(TASK-438.2)——
    /// ここで再同期しないと、git 状態が届いてもセグメントの有効判定が更新されない。
    func gitContextDidChange() {
        refreshDiff()
        refreshToolbarState()
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
