import Foundation

/// サイドバーの表示設定 4 値の**この窓でのライブ値**(ADR 0002「窓の状態」)。
///
/// `FileListModel` から分けているのは、この 4 値がモデル自身からほとんど読まれない
/// から。実測(TASK-604.6 着手時)では `sortOrder` / `showHiddenFiles` / `layoutMode` は
/// `FileListModel` 内から一度も読まれておらず、読み手は全部外側だった。
/// `SidebarTransientState`(保存値の対を持たない一時的な見せ方)と並ぶ兄弟型。
///
/// **この窓での真実の源はここ。** アプリ全体の保存値(`SidebarDisplayDefaults`)は
/// 窓の生成時に読む初期値にすぎず、生きている窓は読み直さない(読み直すと他窓の操作が
/// 後から効く)。
///
/// **書き込み口は下の 2 メソッドだけ**で、`settings` は `private(set)`。かつては
/// 「変更の入口は `SidebarListingCoordinator.applyDisplayChange` の 1 本だけ」を doc
/// コメントで宣言していたが、それは守られず `ViewerDisplayOptionsApplier` が
/// 直接代入していた。入口の区別を型に持たせて、doc ではなく構造で分ける。
@MainActor
@Observable
final class SidebarDisplayState {
    /// 4 値のスナップショット。既定値への書き戻しとメニュー項目の状態導出は
    /// これをそのまま読む(同じ 1 箇所を読むための窓)。
    private(set) var settings: SidebarDisplaySettings

    init(settings: SidebarDisplaySettings) {
        self.settings = settings
    }

    /// 一覧の並び順(フォルダー優先 / アルファベット順)。
    var sortOrder: SortOrder {
        settings.sortOrder
    }

    /// 不可視ファイル(ドットファイル)を一覧に出すか。
    /// サイドバーのアイコンボタン・メニュー・ショートカットの見た目もこの値を読む。
    var showHiddenFiles: Bool {
        settings.showHiddenFiles
    }

    /// git 変更のあるエントリだけに絞るか。
    var showChangedFilesOnly: Bool {
        settings.showChangedFilesOnly
    }

    /// 行の並べ方(ドリルダウン / ツリー展開)。
    /// View はキー操作の割り当てをこの値で切り替える。
    var layoutMode: SidebarLayoutMode {
        settings.layoutMode
    }

    /// 利用者の操作による変更。**呼んでよいのは
    /// `SidebarListingCoordinator.applyDisplayChange` だけ**——向こうが
    /// 「ライブ値の更新・既定値の書き戻し・値ごとの後処理」を対で走らせる。
    /// ここは値を変えるだけで、書き戻しも後処理も持たない。
    func apply(_ change: SidebarDisplayChange) {
        settings = settings.applying(change)
    }

    /// CLI の `--sort` / `--hidden-files` によるこの起動限りの上書き
    /// (`ViewerDisplayOptionsApplier`)。**既定値を書き換えない**のが `apply` との違いで、
    /// 利用者が設定を変えたわけではないため次に開く窓へ持ち越さない。
    /// メソッドを分けてあるのがその区別の担保(以前は同じ直接代入で見分けが付かなかった)。
    func applyCLIOverride(sortOrder: SortOrder? = nil, showHiddenFiles: Bool? = nil) {
        if let sortOrder { settings.sortOrder = sortOrder }
        if let showHiddenFiles { settings.showHiddenFiles = showHiddenFiles }
    }
}
