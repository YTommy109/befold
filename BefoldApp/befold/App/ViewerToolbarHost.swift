import AppKit

/// ViewerToolbarController がツールバー構築・アクション委譲のために参照する先。
/// ViewerWindowController が実装する。循環参照を避けるため ViewerToolbarController からは weak 参照する。
@MainActor
protocol ViewerToolbarHost: AnyObject {
    /// サイドバーのファイル一覧と選択状態。
    var fileListModel: FileListModel { get }
    /// 戻る/進むアイテムの有効状態と履歴メニューの中身。写しを経由せずここを読む(TASK-458)。
    var navigationHistory: NavigationHistory { get }
    /// 表示状態(ファイル種別・ソース表示可否・行番号表示)。
    var store: ViewerStore { get }
    /// いま何ができるか。ツールバーの有効/無効はここだけを見る(ADR 0002)。
    var capabilities: ViewerCapabilities { get }
    /// いまの表示モード。セグメントの選択位置に使う。
    var effectiveDisplayMode: ViewerDisplayMode { get }
    /// モード切替セグメントの選択変更を反映する。
    func setDisplayMode(_ newValue: ViewerDisplayMode)
    /// そのモードをいま選べるか(セグメントごとの有効/無効に使う)。
    func canSelect(_ mode: ViewerDisplayMode) -> Bool
    /// 差分レイアウト(インライン/左右分割)の切替。差分表示中に差分セグメントを
    /// 再クリックしたときに呼ばれる。
    func toggleDiffLayout(_ sender: Any?)
    /// 差分レイアウトが左右分割か。差分セグメントのアイコン・説明に使う。
    var isDiffLayoutSideBySide: Bool { get }
    /// 戻る/進むアイテム・メニュー表現から呼ばれる履歴ナビゲーション。
    func navigateHistory(by offset: Int)
    /// 行番号ボタン・メニュー表現から呼ばれる行番号表示トグル。
    func toggleLineNumbers(_ sender: Any?)
    /// 現在ファイルがブックマーク済みかどうか。ブックマークボタンのアイコン・色に使う。
    var isBookmarked: Bool { get }
    /// ブックマークボタン・メニュー表現から呼ばれるブックマークトグル。
    func toggleBookmark(_ sender: Any?)
}
