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

    /// その切り替えが今 ON か。**チェックマークを出す側は全部ここを読む**——View
    /// メニュー(`SidebarDisplayMenuState`)とサイドバーの ⋯ メニュー
    /// (`SidebarOverflowItem`)が別々に符号化していると、片方だけ直したときに
    /// 「メニューにはチェックが付くのに ⋯ には付かない」形が作れる(TASK-592)。
    ///
    /// **`default` を置かない。** 切り替えを足したときに「適用はするがチェックは
    /// 決して付かない」へ静かに倒れるため、網羅をコンパイラに見張らせる。
    /// 表示形式は 2 値なので「ON」はツリー側と決めてある(元の
    /// `SidebarDisplayMenuState.checksTreeLayout` の定義をそのまま引き継ぐ)。
    func isOn(_ change: SidebarDisplayChange) -> Bool {
        switch change {
        case .toggleHiddenFiles: showHiddenFiles
        case .toggleChangedFilesOnly: showChangedFilesOnly
        case .toggleLayoutMode: layoutMode == .tree
        // 並び順だけは反転ではなく「指定した値にする」なので、一致で判定する。
        case let .setSortOrder(order): sortOrder == order
        }
    }
}

/// 窓の生成時に初期値へ混ぜる「指定のあった値」。指定されていない値は nil で表し、
/// 保存された既定値をそのまま使う。
///
/// 出どころは 2 つある。CLI 由来の「この起動限りの上書き」(`--sort` / `--hidden-files`)と、
/// 起点の窓からの引き継ぎ(TASK-593.2)。**個別の引数で持ち回らない**——経路が増えるたびに
/// 引数が伸びて片方だけ通し忘れる(TASK-413 と同型)。
///
/// **4 値すべてを持つ。** ADR 0002 の窓ごと 4 値のうち 2 つだけを運ぶ形にしていると、
/// 「別の窓で開く」で並び順は引き継がれるのにレイアウトと絞り込みだけ既定へ戻る、という
/// 非対称が生まれる。運べる値と運べない値の境界は、この型の外からは見えない。
struct SidebarDisplayOverrides: Equatable {
    var sortOrder: SortOrder?
    var showHiddenFiles: Bool?
    var showChangedFilesOnly: Bool?
    var layoutMode: SidebarLayoutMode?

    /// 指定なし。CLI 以外の経路(Recent メニュー・参照クリックなど)はこれで開く。
    static let none = SidebarDisplayOverrides()

    /// 既定値へ上書きを重ねた初期値。**適用はここ 1 箇所だけ**——値を足したときに
    /// 「型には足したが混ぜ忘れた」形をコンパイラでは捕まえられないため、混ぜる場所を
    /// 1 つに保って `SidebarDisplayOverridesTests` で全値を測る。
    func applied(to settings: SidebarDisplaySettings) -> SidebarDisplaySettings {
        var merged = settings
        if let sortOrder { merged.sortOrder = sortOrder }
        if let showHiddenFiles { merged.showHiddenFiles = showHiddenFiles }
        if let showChangedFilesOnly { merged.showChangedFilesOnly = showChangedFilesOnly }
        if let layoutMode { merged.layoutMode = layoutMode }
        return merged
    }
}

/// サイドバー表示 4 値への変更。`SidebarListingCoordinator.applyDisplayChange(_:)` が
/// 受け取る唯一の語彙。
///
/// トグルの入口(メニュー・サイドバーヘッダー・ショートカット)を 1 本の API へ集めるために
/// enum にしてある。値ごとにメソッドを生やすと、後処理(再列挙するのか・展開を捨てるのか・
/// git を取り直すのか)の非対称が入口ごとに写経され、片方だけ直す事故になる。
/// **`Hashable`** なのは、⋯ メニューが項目の identity にこの値を使うため
/// (`SidebarHeaderControls` の `ForEach(id: \.change)`、TASK-592)。
enum SidebarDisplayChange: Hashable {
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
    /// 届け先が無い状態で押せてはならない)。**サイドバーを持てない窓でも false**
    /// ——スライド窓には切り替える先の一覧が無く、押しても結果が見えない(TASK-593)。
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
    ///   - allowsSidebar: そのウィンドウがサイドバーを持てるか(`ViewerWindowKind.allowsSidebar`)。
    ///     スライド窓では 3 項目すべてが対象を持たない。`canFilterChangedFiles` と同じ理由で
    ///     **既定値を持たせない**。
    init(
        activeWindow settings: SidebarDisplaySettings?, canFilterChangedFiles: Bool,
        allowsSidebar: Bool
    ) {
        isEnabled = settings != nil && allowsSidebar
        // 3 値とも `isOn(_:)` から導く。⋯ メニューのチェックと同じ定義を読むため、
        // 「メニューと ⋯ でチェックの意味がずれる」形を作れない(TASK-592)。
        hidesHiddenFiles = settings?.isOn(.toggleHiddenFiles) ?? false
        checksChangedFilesOnly = settings?.isOn(.toggleChangedFilesOnly) ?? false
        checksTreeLayout = settings?.isOn(.toggleLayoutMode) ?? false
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
