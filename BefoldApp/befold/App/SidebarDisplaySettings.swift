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

/// CLI 由来の「この起動限りの上書き」。指定のあった値だけ、窓の生成時に初期値へ混ぜる。
///
/// `--sort` / `--hidden-files` を個別の引数で持ち回ると、経路が増えるたびに引数が伸びて
/// 片方だけ通し忘れる(TASK-413 と同型)。**指定されていない = nil** をここで表し、
/// 保存された既定値は書き換えない。
struct SidebarDisplayOverrides: Equatable {
    var sortOrder: SortOrder?
    var showHiddenFiles: Bool?

    /// 指定なし。CLI 以外の経路(Recent メニュー・参照クリックなど)はこれで開く。
    static let none = SidebarDisplayOverrides()
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

extension FileListModel {
    /// この窓のサイドバー表示 4 値のスナップショット。
    /// 既定値への書き戻しと、メニュー項目の状態導出が同じ 1 箇所を読むための窓。
    var displaySettings: SidebarDisplaySettings {
        SidebarDisplaySettings(
            showHiddenFiles: showHiddenFiles, showChangedFilesOnly: showChangedFilesOnly,
            layoutMode: layoutMode, sortOrder: sortOrder
        )
    }
}

/// View メニューのサイドバー表示 3 項目の状態。
///
/// 判定を `AppDelegate.validateMenuItem` の中に書かず値として切り出しているのは、
/// **アクティブウィンドウが無いときの扱い**(項目を無効化する)を含めて headless に
/// 検証できるようにするため。`NSApp.mainWindow` に依存する解決は呼び出し側に残す。
struct SidebarDisplayMenuState: Equatable {
    /// 項目を選べるか。操作対象の窓が無ければ false(4 値は窓ごとのライブ値なので、
    /// 届け先が無い状態で押せてはならない)。
    let isEnabled: Bool
    /// 不可視ファイル項目が「隠す」を表すか(表示中なら true)。
    let hidesHiddenFiles: Bool
    /// 「変更ファイルのみ表示」にチェックを付けるか。
    let checksChangedFilesOnly: Bool
    /// 「サイドバーをツリー表示」にチェックを付けるか。
    let checksTreeLayout: Bool
    /// 「変更ファイルのみ表示」を選べるか。git 管理下でだけ意味を持つ(TASK-537)。
    ///
    /// `isEnabled` と分けているのは、無効になる理由が違うため。あちらは「届け先の窓が
    /// 無い」で 3 項目すべてに効き、こちらは「絞り込む git 状態が無い」でこの項目だけに効く。
    let canFilterChangedFiles: Bool

    /// - Parameters:
    ///   - settings: アクティブウィンドウの現在値。窓が無ければ nil。
    ///   - canFilterChangedFiles: そのウィンドウで「変更のあるファイルのみ」を出してよいか
    ///     (`FileListModel.canFilterChangedFiles`)。窓が無ければ `isEnabled` が false に
    ///     なるので値は問わない。**既定値を持たせない**——渡し忘れが静かに
    ///     「常に出す / 常に出さない」へ倒れる形を作らないため。
    init(activeWindow settings: SidebarDisplaySettings?, canFilterChangedFiles: Bool) {
        isEnabled = settings != nil
        hidesHiddenFiles = settings?.showHiddenFiles ?? false
        checksChangedFilesOnly = settings?.showChangedFilesOnly ?? false
        checksTreeLayout = settings?.layoutMode == .tree
        self.canFilterChangedFiles = canFilterChangedFiles
    }

    /// その項目を選べるか。**項目ごとの条件はここだけが持つ。**
    ///
    /// `validateMenuItem` の中で項目別に分岐を書くと、GUI を起動しないと検証できない場所へ
    /// 判定が漏れ出す。ここへ集めておけば「git 管理外では変更ファイルのみだけが無効」
    /// という判断そのものをユニットテストで固定できる(TASK-537)。
    func isEnabled(for change: SidebarDisplayChange) -> Bool {
        switch change {
        // 絞り込む git 状態が無いフォルダーでは押しても何も起きない。
        case .toggleChangedFilesOnly: isEnabled && canFilterChangedFiles
        case .toggleHiddenFiles, .toggleLayoutMode, .setSortOrder: isEnabled
        }
    }
}
