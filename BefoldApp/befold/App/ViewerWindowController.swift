import AppKit
import BefoldKit
import BefoldRenderKit
import SwiftUI

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
///
/// この型自身が持つのは**依存の保持と生成手順**だけで、実際の仕事は責務ごとの拡張と
/// 協働オブジェクトへ分かれている。どこに何があるかは次のとおり。
///
/// | 置き場所 | 責務 |
/// |---|---|
/// | `ViewerWindowAssembler` | ウィンドウ生成時の組み立てと配線(分割ビュー・サイドバー・WebView コマンド・購読) |
/// | `+FileNavigation` | 提示対象の移動(ファイル切替・リネーム追随・フォルダー移動・履歴) |
/// | `ViewerDocumentPresenter` | 文書の状態の遷移(表示モード・倍率・スクロール位置)と提示開始の 3 契機 |
/// | `+Capabilities` | 提示状態からの能力導出(ADR 0002 段 2) |
/// | `ViewerDiffPresenter` | git 差分の非同期取得・世代管理・レイアウト設定 |
/// | `+MenuActions` | メニュー/ツールバー由来の @objc アクションの受け口(有効判定の対応表は `ViewerMenuValidator`) |
/// | `+References` | 本文中のリンク・パス参照を開く(右クリックメニューは `ReferenceMenuPresenter`) |
/// | `+SidebarHost` / `+Renderer` / `+WindowDelegate` | 各プロトコル準拠(外から来る契機の受け口) |
/// | `ViewerWindowChrome` | NSWindow そのものの生成・外観・フレーム決定(窓を 1 枚しか知らない) |
final class ViewerWindowController: NSWindowController {
    /// 表示状態(ファイル種別・ソース表示可否・行番号表示)。ViewerToolbarHost 経由でツールバーにも公開する。
    let store: ViewerStore
    /// ファイル毎の永続表示状態(倍率・表示モード・スクロール位置・サイドバー開閉・
    /// ウィンドウフレーム)の束。読み書きするのは `ViewerDocumentPresenter` / `+FileNavigation` /
    /// `+Renderer` / `+WindowDelegate` と、WebView コマンドへの受け渡し(`ViewerWindowAssembler`)。
    let perFileState: PerFileStateStore
    /// git 差分の取得・世代管理・レイアウト設定。差分に関する状態はすべて向こう側に置く。
    /// 生成は init 1 箇所きり(host に self を要るため lazy)。
    lazy var diffPresenter = ViewerDiffPresenter(
        loader: diffLoader, gitFileIndex: gitFileIndex, store: store,
        displayPreference: diffDisplayPreference,
        currentURL: { [weak self] in self?.fileURL },
        capabilities: { [weak self] in self?.capabilities ?? .none }
    )
    /// 差分のレイアウト設定。全ウィンドウ共有(差分を出すかどうかは store の表示モードが持つ)。
    /// 判断は diffPresenter が持ち、ここは生成時の受け渡しと共有インスタンスの照合のために保つ。
    let diffDisplayPreference: DiffDisplayPreference
    /// 差分の取得元。全ウィンドウで 1 個を共有する(生成元は ViewerWindowManager 一箇所)。
    /// 機能が無効なビルドでは nil で、git diff を一切実行しない。
    let diffLoader: GitDiffLoader?

    /// 差分表示モードかどうか。実体は diffPresenter(ここは外向きの入口)。
    var isDiffShown: Bool {
        diffPresenter.isDiffShown
    }

    /// 差分レイアウトが左右分割か(ViewerToolbarHost の要求)。
    var isDiffLayoutSideBySide: Bool {
        diffPresenter.isLayoutSideBySide
    }

    /// 表示中ファイルの差分を取り直す。契機は表示モード遷移(`ViewerDocumentPresenter` へ
    /// 注入するクロージャ)と git 状態の反映(`+SidebarHost` の `gitContextDidChange`)の 2 つ。
    /// どちらもここを通す(`diffPresenter.refresh()` を直接呼ぶと、TASK-330 の
    /// 「バッジと差分の更新契機を 1 つにする」をこの doc から追う人が生きた契機を見落とす)。
    func refreshDiff() {
        diffPresenter.refresh()
    }

    /// 直近の取り直しの反映タスク。完了を待てる観測点はここだけ(TASK-437)。
    var diffRefreshTask: Task<Void, Never>? {
        diffPresenter.refreshTask
    }

    /// 検索の 3 トグル。使うのは分割ビューの組み立て(`ViewerWindowAssembler`)だけ。
    let findOptionsPreference: FindOptionsPreference
    /// 見出しジャンプの設定。窓の生成時に読んだ出発点と、変更の書き戻し口。
    let headingJump: HeadingJumpLevelBinding
    /// コードフォント設定。使うのは分割ビューの組み立てと、設定変更時の再注入(`+SidebarHost`)。
    let codeFontPreference: CodeFontPreference
    /// CSV/TSV の数値表示設定。ViewerWindowManager と同じ 1 個を受け取る。
    let csvNumberFormatPreference: CsvNumberFormatPreference
    /// ブックマークの永続化。使うのはブックマークのトグルと状態参照(`+MenuActions`)だけ。
    let bookmarkStore: BookmarkStore
    /// ウィンドウ生成時のサイドバー初期開閉状態。解決(記憶の引き継ぎ・CLI からの強制表示など)は
    /// ViewerWindowManager.openViewer が行い、ここでは結果を受け取って渡すだけにする。
    let initialSidebarCollapsed: Bool
    /// 別のタブ/ウィンドウでファイルを開く処理。タブ結合の基準にするため自分のウィンドウも渡す。
    /// 本番では ViewerWindowManager 経由で注入する。
    let openFileElsewhere: (URL, OpenDisposition, NSWindow?) -> Void
    /// 外部 URL(http/https)をブラウザで開く処理。本番では NSWorkspace 経由。
    /// テストが実ブラウザを起動せずに済むよう注入可能にしている。
    /// 渡す先は referenceMenu と referenceActions.openExternal の 2 箇所だけ。
    /// 後者は `+References` にあるため file-private では届かず internal にしている
    /// (外から直接呼ぶためのものではない)。
    let externalOpener: (URL) -> Void
    /// 生成した SplitViewController への型消去参照。contentViewController が保持するため weak。
    /// 代入は組み立て時(`ViewerWindowAssembler`)、参照は CLI の `--sidebar`/`--no-sidebar` 適用(`+FileNavigation`)。
    weak var sidebarCollapsible: (any SidebarCollapsible)?
    /// 二本指スワイプによるファイル履歴ナビゲーション検知。
    /// 開始は `ViewerWindowAssembler`、停止は `+WindowDelegate` の windowWillClose。
    var swipeMonitor: SwipeHistoryMonitor!
    /// ツールバー(モード切替・戻る/進む・行番号)の構築とライブ状態更新を担う。
    private(set) var toolbarController: ViewerToolbarController!
    /// テスト(@testable)が renderer を差し込んで rename 追随の配線を検証できるよう
    /// private にしない(本体アプリのコードからは ViewerWebView の配線経由でのみ使う)。
    let webViewProxy = WebViewProxy()
    /// WebView 操作系メニューアクション(ズーム・印刷・検索・スクロール位置保存)の実処理。
    /// 生成は init 1 箇所きり。使うのは `+MenuActions` / `ViewerDocumentPresenter` /
    /// `+FileNavigation` / `+SidebarHost`。
    private(set) var webViewCommands: WebViewCommandController!
    /// 表示モード・倍率・スクロール位置の遷移(ADR 0002 段 1)。提示状態の判断はすべて向こう側。
    /// webViewCommands の生成後にしか作れないため lazy(参照はどれも init の後段以降)。
    lazy var documentPresenter = ViewerDocumentPresenter(
        store: store, perFileState: perFileState, webViewCommands: webViewCommands,
        currentDocument: currentDocument,
        canSelect: { [weak self] mode in self?.canSelect(mode) ?? false },
        refreshToolbar: { [weak self] in self?.refreshUIState() },
        refreshDiff: { [weak self] in self?.refreshDiff() }
    )

    // MARK: - 提示状態の遷移(実体は documentPresenter。ここは外から呼ばれる入口)

    /// 表示モードを変える唯一の入口(ViewerToolbarHost の要求。メニュー ⌘1〜⌘3 も通る)。
    func setDisplayMode(_ newValue: ViewerDisplayMode) {
        documentPresenter.setDisplayMode(newValue)
    }

    /// 永続化を伴わない表示モードの反映(復元・リネーム追随)。
    func applyDisplayMode(_ newValue: ViewerDisplayMode) {
        documentPresenter.applyDisplayMode(newValue)
    }

    /// CLI の `--source` / `--preview` の適用。
    func applyCLIDisplayMode(isSourceMode: Bool) {
        documentPresenter.applyCLIDisplayMode(isSourceMode: isSourceMode)
    }

    /// 提示開始。保存値を読んでよい 3 契機のうちの 2 つ(オープン・ファイル切替)から呼ぶ。
    func beginPresentingDocument(at url: URL) {
        documentPresenter.beginPresentingDocument(at: url)
    }

    /// 書き換え前の save-before-mutate。
    func saveScrollPositionBeforeTransition() {
        documentPresenter.saveScrollPositionBeforeTransition()
    }

    /// 退場側の保存完了をライブな復元値へ追いつかせる。
    func applySavedScrollPositionToLiveValue(_ position: Double, for url: URL, mode: ViewerBridge.ViewMode) {
        documentPresenter.applySavedScrollPositionToLiveValue(position, for: url, mode: mode)
    }

    /// 表示モードの唯一の真実の源は store。二重保持を避けるため委譲する。
    var displayMode: ViewerDisplayMode {
        store.displayMode
    }

    /// セグメント・メニューのチェックが指し示すモード(詳細は ViewerStore を参照)。
    var effectiveDisplayMode: ViewerDisplayMode {
        store.effectiveDisplayMode
    }

    var isSourceMode: Bool {
        store.isSourceMode
    }

    /// 提示中の文書 URL への共有参照。窓の子(`ViewerDocumentPresenter` /
    /// `WebViewCommandController`)へ同じ 1 個を渡し、旧 URL の捕捉を構造で防ぐ。
    let currentDocument: CurrentDocumentRef
    /// 現在表示中ファイルの URL。保持先は store 一箇所(store.currentURL)。ここでは複製せず委譲する。
    var fileURL: URL {
        currentDocument.url
    }

    /// サイドバー(一覧・選択同期・フォルダ移動)と戻る/進む履歴を担うナビゲータ。
    let sidebar: SidebarNavigator
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    var fileListModel: FileListModel {
        sidebar.fileListModel
    }

    /// このウィンドウの戻る/進む履歴(読み取り専用)。ツールバーとメニュー判定は
    /// 写しではなくこれを直接読む(TASK-458)。
    var navigationHistory: NavigationHistory {
        sidebar.navigationHistory
    }

    /// ウィンドウイベントの通知先。ViewerWindowManager が実装する。
    weak var delegate: ViewerWindowControllerDelegate?

    /// このウィンドウが属する git リポジトリ(worktree の場合はそのルート)。
    /// 非 git ファイルの場合は nil。ViewerWindowManager.openViewer が解決結果を設定する。
    var repositoryRoot: URL?

    /// git 追跡ファイルの索引。本番では ViewerWindowManager が持つ単一インスタンスが
    /// 注入され、全ウィンドウで共有する。
    let gitFileIndex: any GitFileIndexing
    /// パス参照の解決(索引の先読み・クリック時のオープン・表示時の一括解決)を担う。
    /// fileReader は store と共有する(既存の fileExists/isExistingFile 共有と同じ理由で
    /// InMemoryFileReader 注入テストと整合させる)。
    lazy var referenceCoordinator = ReferenceResolutionCoordinator(
        baseURL: { [weak self] in self?.fileURL }, actions: referenceActions,
        fileReader: store.fileReader, gitIndex: gitFileIndex
    )
    /// 参照の右クリックメニュー(項目定義・表示・実行)。`@objc` アクションを含めて向こう側に閉じる。
    lazy var referenceMenu = ReferenceMenuPresenter(
        relativePathForCopy: { [weak self] url in self?.fileListModel.relativePathForCopy(url) },
        openReference: { [weak self] url, disposition in self?.openReference(url, disposition: disposition) },
        externalOpener: externalOpener
    )

    // MARK: - Initialization

    /// 生成手順は 3 段に分かれる。**この並びには順序制約があり、各段の間に
    /// 「なぜその順でなければならないか」をコメントで残してある。** 工程の中身は
    /// `ViewerWindowAssembler.swift` へ移してあるが、順序はここでしか読めない。
    ///
    /// 1. `super.init` 前 — 保存プロパティの確定とウィンドウ・サイドバーの生成
    /// 2. `super.init` 直後 — self を要る協働オブジェクトの生成とコンテンツの取り付け
    /// 3. 最後 — 購読の配線と提示開始
    ///
    /// - Parameter displayDefaults: 本番では必ず AppDelegate → ViewerWindowManager から
    ///   注入される単一の共有インスタンスを渡すこと。デフォルト値は、不可視ファイル挙動に
    ///   無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    /// - Parameter perFileState: 同上。ファイル毎の永続表示状態(倍率・表示モード・
    ///   スクロール位置)の束。これらの挙動に無関心なテストが省略できるようにする。
    /// - Parameter bookmarkStore: 同上。ブックマーク挙動に無関心なテストが省略できるようにする。
    /// - Parameter gitFileIndex: git 追跡ファイルの索引。本番では ViewerWindowManager が持つ
    ///   単一インスタンスを必ず渡し、同じリポジトリを開く複数ウィンドウで照合索引と
    ///   `git ls-files` の実行を共有する。デフォルトは git を起動しない索引であり、
    ///   パス解決に無関心なテストが省略できるようにするためのもの。実インスタンスを
    ///   デフォルトにすると、注入を書き忘れたときに共有されない別個体が静かに生まれ、
    ///   ウィンドウごとに `git ls-files` を重複実行してしまう。
    /// - Parameter gitStatusStore: サイドバーの git 状態バッジの取得元。本番では AppDelegate が
    ///   生成した単一インスタンスを渡す。デフォルトはルート解決が常に nil を返す無効化状態で、
    ///   注入を省略したテストが git を起動しないことを保証する。
    /// - Parameter store: 同上。表示状態に無関心なテストが省略できるようにする。
    /// - Parameter makeContentView: テスト専用シーム。コンテンツペイン(ViewerContentView / 実 WKWebView)を
    ///   差し替える。既定の nil は本番経路(実 WKWebView を生成する)。サイドバー(FileListView)と
    ///   分割ビュー配線は差し替え対象外。
    /// - Parameter documentRenderer: テスト専用シーム。文書への操作(ズーム・検索・印刷・
    ///   スクロール位置の問い合わせ)の実行先を差し替える。既定の nil は本番経路
    ///   (WKWebView を駆動する WebViewDocumentRenderer)。位置の問い合わせは JS の
    ///   ラウンドトリップを挟むため、完了タイミングを制御したいテストがここを使う。
    /// - Parameter openFileElsewhere: 同上。別タブ/別ウィンドウでのオープン先。デフォルトは AppDelegate 経由。
    /// - Parameter externalOpener: 同上。外部 URL(http/https)を開く処理。デフォルトは NSWorkspace 経由。
    /// 共有物を受け取る引数に既定値を付けない理由と、既定値を残してある引数の区別は
    /// `ViewerWindowManager.init` の doc コメントを参照(同じ規則が両方に掛かる)。
    /// この型では `gitStatusStore` の既定値だけが例外で、それは共有インスタンスの
    /// 受け渡しではなく「git 状態を持たない縮退状態」を表す(`gitFileIndex` の既定が
    /// `DisabledGitFileIndex` なのと同じ)。
    init(
        fileURL: URL, defaults: UserDefaults = .standard,
        displayDefaults: SidebarDisplayDefaults,
        diffDisplayPreference: DiffDisplayPreference,
        diffLoader: GitDiffLoader? = nil,
        findOptionsPreference: FindOptionsPreference,
        headingJumpLevelDefaults: HeadingJumpLevelDefaults,
        codeFontPreference: CodeFontPreference,
        csvNumberFormatPreference: CsvNumberFormatPreference,
        perFileState: PerFileStateStore,
        bookmarkStore: BookmarkStore,
        gitFileIndex: any GitFileIndexing = DisabledGitFileIndex(),
        gitStatusStore: GitStatusStore = GitStatusStore(),
        initialSidebarCollapsed: Bool = true,
        initialFrameDescriptor: String? = nil,
        // CLI の `--sort` による初期並び順の指定。nil なら保存された既定値から始める。
        initialSortOrder: SortOrder? = nil,
        // CLI の `--hidden-files`/`--no-hidden-files` による初期値の指定。
        // nil なら保存された既定値から始める。この起動限りの上書きで既定値は書き換えない。
        initialShowHiddenFiles: Bool? = nil,
        // 起点となった窓が列挙済みの一覧。同じフォルダなら出発点として引き継ぎ、
        // 「空 → 列挙 → 描画」の 2 段階を通らせない(TASK-532)。引き継げるかの判定は
        // SidebarListingSeed.canApply(to:) が持つ。nil なら従来どおり空から始める。
        initialListing: SidebarListingSeed? = nil,
        showLineNumbersOverride: Bool? = nil,
        sourceModeOverride: Bool? = nil,
        store: ViewerStore? = nil,
        makeContentView: (() -> AnyView)? = nil,
        documentRenderer: (any DocumentRendering)? = nil,
        openFileElsewhere: @escaping (URL, OpenDisposition, NSWindow?) -> Void = { url, disposition, source in
            AppDelegate.shared?.openViewer(for: url, disposition: disposition, relativeTo: source)
        },
        externalOpener: @escaping (URL) -> Void = { url in NSWorkspace.shared.open(url) }
    ) {
        self.perFileState = perFileState
        self.diffDisplayPreference = diffDisplayPreference
        self.diffLoader = diffLoader
        self.findOptionsPreference = findOptionsPreference
        // 保存値を読むのは窓の生成時のこの 1 回だけ。以後は記録口しか触らない。
        headingJump = headingJumpLevelDefaults.binding
        self.codeFontPreference = codeFontPreference
        self.csvNumberFormatPreference = csvNumberFormatPreference
        self.bookmarkStore = bookmarkStore
        self.gitFileIndex = gitFileIndex
        self.initialSidebarCollapsed = initialSidebarCollapsed
        self.openFileElsewhere = openFileElsewhere
        self.externalOpener = externalOpener
        let store = store ?? ViewerStore(defaults: defaults)
        // store が呼び出し元から明示注入された場合でも上書きが反映されるよう、
        // store の生成元にかかわらずここで一律に適用する(sourceModeOverride と同じ方針)。
        if let showLineNumbersOverride { store.lineNumbersSetting.applyOverride(showLineNumbersOverride) }
        self.store = store
        currentDocument = CurrentDocumentRef(store: store, initialURL: fileURL)
        sidebar = ViewerWindowAssembler.makeSidebarNavigator(
            fileURL: fileURL, displayDefaults: displayDefaults,
            overrides: SidebarDisplayOverrides(
                sortOrder: initialSortOrder, showHiddenFiles: initialShowHiddenFiles
            ),
            gitFileIndex: gitFileIndex, gitStatusStore: gitStatusStore
        )
        let window = ViewerWindowChrome.makeWindow(fileURL: fileURL)

        super.init(window: window)

        // ここから先は self を使う。toolbarController は self(ViewerToolbarHost)を要るため
        // super.init より前には作れない。ツールバーの生成・デリゲート設定・取り付けの
        // 順序制約は ViewerToolbarController.init の中に閉じている。
        toolbarController = ViewerToolbarController(window: window, host: self)
        webViewCommands = ViewerWindowAssembler.makeWebViewCommands(
            for: self, documentRenderer: documentRenderer
        )
        // contentViewController の設定でウィンドウがビューのフィッティングサイズに
        // リサイズされるため、フレームの確定はその後に行う。
        window.contentViewController = ViewerWindowAssembler.makeSplitViewController(
            for: self, contentOverride: makeContentView
        )
        ViewerWindowChrome.applyInitialFrame(
            initialFrameDescriptor, to: window,
            isOccupied: ViewerWindowAssembler.isOriginOccupiedByAnotherViewer(excluding: window)
        )
        // delegate の設定はフレーム確定後にする。init 中のリサイズ
        // (contentViewController 設定によるフィッティングサイズ化など)が
        // windowDidResize 経由で保存されるのを防ぐ
        window.delegate = self
        swipeMonitor = ViewerWindowAssembler.makeSwipeMonitor(for: self, on: window)
        ViewerWindowAssembler.wirePresentationTargetChange(for: self)
        ViewerWindowAssembler.openInitialDocument(
            for: self, at: fileURL, adopting: initialListing
        )
        // クリック時解決(pathResolver)の git 追跡ファイル索引を先読みしておく。
        referenceCoordinator.warm(forFileAt: fileURL)
        // 直接開いた場合も、切替(performFileSwitch)と同じく保存済みのソース表示モードを復元する。
        // CLI から --source/--preview が指定された場合はそちらを優先し、保存値は書き換えない(この起動限りの上書き)。
        // 上書きの適用は applyCLIDisplayMode に寄せる。既に開いているウィンドウを指定して
        // 開き直した経路(ViewerWindowManager.openViewer)と同じ降格規則を通すため。
        if let sourceModeOverride {
            applyCLIDisplayMode(isSourceMode: sourceModeOverride)
        } else {
            documentPresenter.applyRestoredDisplayMode(for: fileURL)
        }
        // 提示開始(オープン)。倍率とスクロール位置の保存値を読むのはここと performFileSwitch だけ。
        // 表示モードのキーから引くため、applyDisplayMode の後に呼ぶこと。
        beginPresentingDocument(at: fileURL)
        sidebar.recordHistory()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - ViewerToolbarHost

/// ツールバーが要る 12 個の要求は、責務ごとの拡張(`+Capabilities` / `+MenuActions` /
/// `+FileNavigation`)と、協働オブジェクトへ委譲する本体のファサード
/// (`ViewerDocumentPresenter` 宛の「提示状態の遷移」節と、`ViewerDiffPresenter` 宛の
/// `isDiffShown` / `isDiffLayoutSideBySide`)がそれぞれ満たしている。
extension ViewerWindowController: ViewerToolbarHost {}
