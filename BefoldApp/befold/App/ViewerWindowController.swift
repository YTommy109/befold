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
/// | `+Assembly` | ウィンドウ生成時の組み立てと配線(分割ビュー・サイドバー・WebView コマンド・購読) |
/// | `+FileNavigation` | 提示対象の移動(ファイル切替・リネーム追随・フォルダー移動・履歴) |
/// | `+Presentation` | 文書の状態の遷移(表示モード・倍率・スクロール位置)と提示開始の 3 契機 |
/// | `+Capabilities` | 提示状態からの能力導出(ADR 0002 段 2) |
/// | `+DiffPresentation` | git 差分の非同期取得と世代管理 |
/// | `+MenuActions` | メニュー/ツールバー由来の @objc アクションと validate の対応表 |
/// | `+References` | 本文中のリンク・パス参照を開く / 右クリックメニュー |
/// | `+SidebarHost` / `+Renderer` / `+WindowDelegate` | 各プロトコル準拠(外から来る契機の受け口) |
/// | `ViewerWindowChrome` | NSWindow そのものの生成・外観・フレーム決定(窓を 1 枚しか知らない) |
final class ViewerWindowController: NSWindowController {
    /// 表示状態(ファイル種別・ソース表示可否・行番号表示)。ViewerToolbarHost 経由でツールバーにも公開する。
    let store: ViewerStore
    /// ファイル毎の永続表示状態(倍率・表示モード・スクロール位置・サイドバー開閉・
    /// ウィンドウフレーム)の束。読み書きするのは `+Presentation` / `+FileNavigation` /
    /// `+Renderer` / `+WindowDelegate` と、WebView コマンドへの受け渡し(`+Assembly`)。
    let perFileState: PerFileStateStore
    /// 差分のレイアウト設定。全ウィンドウ共有(差分を出すかどうかは store の表示モードが持つ)。
    /// 参照は `+DiffPresentation` と `+MenuActions` に集約している。
    let diffDisplayPreference: DiffDisplayPreference
    /// 差分の取得元。全ウィンドウで 1 個を共有する(生成元は ViewerWindowManager 一箇所)。
    /// 機能が無効なビルドでは nil で、git diff を一切実行しない。
    let diffLoader: GitDiffLoader?
    /// 検索の 3 トグル。使うのは分割ビューの組み立て(`+Assembly`)だけ。
    let findOptionsPreference: FindOptionsPreference
    /// コードフォント設定。使うのは分割ビューの組み立てと、設定変更時の再注入(`+SidebarHost`)。
    let codeFontPreference: CodeFontPreference
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
    let externalOpener: (URL) -> Void
    /// 生成した SplitViewController への型消去参照。contentViewController が保持するため weak。
    /// 代入は組み立て時(`+Assembly`)、参照は CLI の `--sidebar`/`--no-sidebar` 適用(`+FileNavigation`)。
    weak var sidebarCollapsible: (any SidebarCollapsible)?
    /// 二本指スワイプによるファイル履歴ナビゲーション検知。
    /// 開始は `+Assembly`、停止は `+WindowDelegate` の windowWillClose。
    var swipeMonitor: SwipeHistoryMonitor!
    /// ツールバー(モード切替・戻る/進む・行番号)の構築とライブ状態更新を担う。
    private(set) var toolbarController: ViewerToolbarController!
    /// テスト(@testable)が renderer を差し込んで rename 追随の配線を検証できるよう
    /// private にしない(本体アプリのコードからは ViewerWebView の配線経由でのみ使う)。
    let webViewProxy = WebViewProxy()
    /// WebView 操作系メニューアクション(ズーム・印刷・検索・スクロール位置保存)の実処理。
    /// 生成は init 1 箇所きり。使うのは `+MenuActions` / `+Presentation` /
    /// `+FileNavigation` / `+SidebarHost`。
    private(set) var webViewCommands: WebViewCommandController!
    /// cmd+U でソース系モードを離れた直前の「どのソース系モードだったか」と、その時のファイル。
    /// レンダリング表示中しか値を持たない(ソース系モードへ入った時点で setDisplayMode が捨てる)。
    /// 保存値からは復元できない: 離脱側の cmd+U が保存値を `.rendered` で上書きするため、
    /// 戻る側が保存値を読むと必ず `.source` に落ちる(TASK-370)。
    /// 記憶するのは `+MenuActions` の toggleSourceView、捨てるのは `+Presentation` の
    /// setDisplayMode。この 2 箇所以外から触らないこと。
    var sourceToggleReturn: (pathKey: String, mode: ViewerDisplayMode)?
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

    /// ウィンドウ起動時の初期ファイル URL。可変な現在 URL の唯一の保持先は store.currentURL であり、
    /// これは store がまだ URL を持たない init 直後の一瞬(実際には store.openFile 済みのため到達しない)を
    /// 型的に埋めるためのブートストラップ定数。rename / switch では更新しない。
    private let initialFileURL: URL
    /// 現在表示中ファイルの URL。保持先は store 一箇所(store.currentURL)。ここでは複製せず委譲する。
    var fileURL: URL {
        store.currentURL ?? initialFileURL
    }

    /// サイドバー(一覧・選択同期・フォルダ移動)と戻る/進む履歴を担うナビゲータ。
    let sidebar: SidebarNavigator
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    var fileListModel: FileListModel {
        sidebar.fileListModel
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
        host: self, fileReader: store.fileReader, gitIndex: gitFileIndex
    )

    // MARK: - Initialization

    /// 生成手順は 3 段に分かれる。**この並びには順序制約があり、各段の間に
    /// 「なぜその順でなければならないか」をコメントで残してある。** 工程の中身は
    /// `ViewerWindowController+Assembly.swift` へ移してあるが、順序はここでしか読めない。
    ///
    /// 1. `super.init` 前 — 保存プロパティの確定とウィンドウ・サイドバーの生成
    /// 2. `super.init` 直後 — self を要る協働オブジェクトの生成とコンテンツの取り付け
    /// 3. 最後 — 購読の配線と提示開始
    ///
    /// - Parameter sidebarDisplayPreference: 本番では必ず AppDelegate → ViewerWindowManager から
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
    init(
        fileURL: URL, defaults: UserDefaults = .standard,
        sidebarDisplayPreference: SidebarDisplayPreference = SidebarDisplayPreference(),
        diffDisplayPreference: DiffDisplayPreference,
        diffLoader: GitDiffLoader? = nil,
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        codeFontPreference: CodeFontPreference = CodeFontPreference(),
        perFileState: PerFileStateStore = PerFileStateStore(),
        bookmarkStore: BookmarkStore,
        gitFileIndex: any GitFileIndexing = DisabledGitFileIndex(),
        gitStatusStore: GitStatusStore = GitStatusStore(),
        initialSidebarCollapsed: Bool = true,
        initialFrameDescriptor: String? = nil,
        initialSortOrder: SortOrder = .foldersFirst,
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
        initialFileURL = fileURL
        self.perFileState = perFileState
        self.diffDisplayPreference = diffDisplayPreference
        self.diffLoader = diffLoader
        self.findOptionsPreference = findOptionsPreference
        self.codeFontPreference = codeFontPreference
        self.bookmarkStore = bookmarkStore
        self.gitFileIndex = gitFileIndex
        self.initialSidebarCollapsed = initialSidebarCollapsed
        self.openFileElsewhere = openFileElsewhere
        self.externalOpener = externalOpener
        let store = store ?? ViewerStore(defaults: defaults)
        // store が呼び出し元から明示注入された場合でも上書きが反映されるよう、
        // store の生成元にかかわらずここで一律に適用する(sourceModeOverride と同じ方針)。
        if let showLineNumbersOverride { store.applyShowLineNumbersOverride(showLineNumbersOverride) }
        self.store = store
        sidebar = ViewerWindowController.makeSidebarNavigator(
            fileURL: fileURL, sidebarDisplayPreference: sidebarDisplayPreference,
            sortOrder: initialSortOrder, gitFileIndex: gitFileIndex, gitStatusStore: gitStatusStore
        )
        let window = ViewerWindowChrome.makeWindow(fileURL: fileURL)

        super.init(window: window)

        // ここから先は self を使う。toolbarController は self(ViewerToolbarHost)を要るため
        // super.init より前には作れない。ツールバーの生成・デリゲート設定・取り付けの
        // 順序制約は ViewerToolbarController.init の中に閉じている。
        toolbarController = ViewerToolbarController(window: window, host: self)
        webViewCommands = makeWebViewCommands(documentRenderer: documentRenderer, fallbackURL: fileURL)
        // contentViewController の設定でウィンドウがビューのフィッティングサイズに
        // リサイズされるため、フレームの確定はその後に行う。
        window.contentViewController = makeSplitViewController(contentOverride: makeContentView)
        ViewerWindowChrome.applyInitialFrame(
            initialFrameDescriptor, to: window,
            isOccupied: ViewerWindowController.isOriginOccupiedByAnotherViewer(excluding: window)
        )
        // delegate の設定はフレーム確定後にする。init 中のリサイズ
        // (contentViewController 設定によるフィッティングサイズ化など)が
        // windowDidResize 経由で保存されるのを防ぐ
        window.delegate = self
        startSwipeMonitor(on: window)
        wirePresentationTargetChange()
        sidebar.attach(to: self)
        // 空で作ったサイドバー一覧をここで埋める(列挙はメインアクター外で走る)。
        sidebar.refreshFileList()
        wireStoreCallbacks()
        store.openFile(fileURL)
        // クリック時解決(pathResolver)の git 追跡ファイル索引を先読みしておく。
        referenceCoordinator.warm(forFileAt: fileURL)
        // 直接開いた場合も、切替(performFileSwitch)と同じく保存済みのソース表示モードを復元する。
        // CLI から --source/--preview が指定された場合はそちらを優先し、保存値は書き換えない(この起動限りの上書き)。
        let restoredMode = perFileState.displayMode.restoredDisplayMode(for: fileURL)
        applyDisplayMode(sourceModeOverride.map { $0 ? ViewerDisplayMode.source : .rendered } ?? restoredMode)
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

/// ツールバーが要る 12 個の要求は、責務ごとの拡張(`+Capabilities` / `+Presentation` /
/// `+MenuActions` / `+DiffPresentation` / `+FileNavigation`)がそれぞれ満たしている。
extension ViewerWindowController: ViewerToolbarHost {}
