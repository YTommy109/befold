import Foundation

/// SidebarNavigator がファイル切替・現在ファイル参照を委譲する先。
/// ViewerWindowController が実装する。循環参照を避けるため SidebarNavigator からは weak 参照する。
@MainActor
protocol SidebarNavigatorHost: AnyObject {
    /// 現在表示中のファイル URL。performFileSwitch により変化するため都度参照する。
    var currentFileURL: URL { get }
    /// サイドバー選択・履歴から要求されたファイル切替の実処理。
    /// 別ウィンドウで開いている・存在しないなど切替できなかった理由は結果で返る。
    @discardableResult
    func performFileSwitch(to url: URL) -> FileSwitchOutcome
    /// 戻る/進む履歴の状態が変化した。AppKit 側 UI(ツールバー)の更新契機。
    func historyStateDidChange()
    /// git 状態(サイドバーのバッジ)が反映された。表示中ファイルの差分など、
    /// バッジと同じ契機で取り直すべきものの更新点。
    ///
    /// 「バッジと差分の更新契機を 1 つにする」判断を、コンパイル時に守らせるための必須メソッド。
    /// 呼び分けを増やすと、契機がまた片方だけに増える(TASK-330)。
    func gitContextDidChange()
}
