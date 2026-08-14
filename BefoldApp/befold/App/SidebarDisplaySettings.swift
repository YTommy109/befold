import Foundation

/// サイドバーの表示設定 4 値をまとめた値型。
///
/// **ウィンドウへ初期値を渡すための運び手**であり、状態そのものではない。窓が生きている
/// 間のライブ値は `FileListModel` が持ち(ADR 0002「窓の状態」)、この型は
/// `SidebarDisplayDefaults`(アプリ全体の既定値)から窓の生成時に 1 回だけ流れる。
///
/// 値型にしているのは、窓側が既定値ストアへの参照を持たないようにするため。参照を持つと
/// 「生きている窓は保存値を読み直さない」という規則が doc コメントでしか守られなくなる。
struct SidebarDisplaySettings: Equatable {
    /// 不可視ファイル(ドットファイル)を一覧に出すか。
    var showHiddenFiles: Bool
    /// git 変更のあるファイルだけに一覧を絞るか。
    var showChangedFilesOnly: Bool
    /// サイドバーの行の並べ方(ドリルダウン / ツリー展開)。
    var layoutMode: SidebarLayoutMode
    /// 一覧の並び順(フォルダー優先 / アルファベット順)。
    var sortOrder: SortOrder

    /// 保存値が無いときの出発点。**本番のウィンドウ生成経路では使わない**
    /// (必ず `SidebarDisplayDefaults.settings` を通す)。
    static let initial = SidebarDisplaySettings(
        showHiddenFiles: false, showChangedFilesOnly: false,
        layoutMode: .drillDown, sortOrder: .foldersFirst
    )
}

/// サイドバー表示 4 値への変更。`SidebarListingCoordinator.applyDisplayChange(_:)` が
/// 受け取る唯一の語彙。
///
/// トグルの入口(メニュー・サイドバーヘッダー・ショートカット)を 1 本の API へ集めるために
/// enum にしてある。値ごとにメソッドを生やすと、後処理(再列挙するのか・展開を捨てるのか・
/// git を取り直すのか)の非対称が入口ごとに写経され、片方だけ直す事故になる。
enum SidebarDisplayChange: Equatable {
    /// 不可視ファイル表示を反転する。
    case toggleHiddenFiles
    /// 「変更ファイルのみ表示」を反転する。
    case toggleChangedFilesOnly
    /// ドリルダウン / ツリー展開を反転する。
    case toggleLayoutMode
    /// 並び順を指定した値にする。
    case setSortOrder(SortOrder)
}

/// アプリ全体の既定値へ最新値を書き戻す口。**読み取りは持たせない。**
///
/// `SidebarListingCoordinator` はこのプロトコルだけを受け取る。読み取り API が無いことで
/// 「生きている窓が保存値を読み直す」経路をコンパイル時に作れなくする(ADR 0002
/// 「窓の状態の規則」2)。doc コメントで禁じるのではなく、型で到達不能にするのが要点。
@MainActor
protocol SidebarDisplayDefaultsRecording {
    /// 4 値の最新値を既定値として記録する。次に開く窓の出発点になる。
    func record(_ settings: SidebarDisplaySettings)
}

/// 新規ウィンドウへ初期値を供給する口。**読めるのはここだけ。**
///
/// 受け取るのは `SidebarNavigator.init`(窓の生成時の 1 回)に限る。init はこの値を
/// **保持しない**ため、窓が生きている間に読み直す経路は構造的に作れない。窓の内側
/// (`SidebarListingCoordinator`)へ渡すのは書き戻し専用の
/// `SidebarDisplayDefaultsRecording` だけ。
@MainActor
protocol SidebarDisplayDefaultsProviding: SidebarDisplayDefaultsRecording {
    /// 新しく開くウィンドウの初期値。
    var settings: SidebarDisplaySettings { get }
}
