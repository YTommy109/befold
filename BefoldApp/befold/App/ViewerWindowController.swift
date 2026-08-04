import AppKit
import BefoldKit
import BefoldRenderKit
import SwiftUI
import WebKit

/// サイドバーへ渡す git 状態の取得クロージャを作る。
///
/// **フィーチャーゲートの判定はこの 1 箇所だけ**で行う(ロジック自体は常時ビルドし、
/// 露出点だけを囲う)。stable 昇格時はこの guard を消して常に store を引く形にすればよい。
@MainActor
private func makeSidebarGitStatusLoader(
    _ store: GitStatusStore
) -> (URL, GitStatusRefreshPolicy) async -> GitStatusResult {
    guard FeatureGate.inProgressFeaturesEnabled else { return { _, _ in .empty } }
    return { directory, policy in await store.statuses(forDirectoryAt: directory, policy: policy) }
}

/// ViewerWindowController のウィンドウイベント(クローズ・rename・キー化など)を
/// 上位のウィンドウ管理層へ通知するプロトコル。ViewerWindowManager が実装する。
@MainActor
protocol ViewerWindowControllerDelegate: AnyObject {
    func viewerWindowWillClose(_ controller: ViewerWindowController)
    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController)
    func viewerWindow(_ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL)
    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    )
    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController)
    func viewerWindowDidToggleChangedFilesOnly(_ controller: ViewerWindowController)
}

/// performFileSwitch の結果。呼び出し元(明示的なファイル選択と履歴ナビゲーション)が
/// 成否で扱いを分けられるよう、単なる Bool ではなく理由を返す。
enum FileSwitchOutcome {
    /// 切替が完了した。
    case switched
    /// 対象ファイルが見つからず切替できなかった(利用者へは警告済み)。
    case failed
}

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
final class ViewerWindowController: NSWindowController {
    private static let defaultContentSize = NSSize(width: 1100, height: 850)

    private let defaults: UserDefaults
    /// 表示状態(ファイル種別・ソース表示可否・行番号表示)。ViewerToolbarHost 経由でツールバーにも公開する。
    let store: ViewerStore
    /// ファイル毎の永続表示状態(倍率・ソース表示モード・スクロール位置)の束。
    private let perFileState: PerFileStateStore
    private let sidebarDisplayPreference: SidebarDisplayPreference
    private let findOptionsPreference: FindOptionsPreference
    private let codeFontPreference: CodeFontPreference
    private let bookmarkStore: BookmarkStore
    /// ウィンドウ生成時のサイドバー初期開閉状態。解決(記憶の引き継ぎ・CLI からの強制表示など)は
    /// ViewerWindowManager.openViewer が行い、ここでは結果を受け取って渡すだけにする。
    private let initialSidebarCollapsed: Bool
    /// 別のタブ/ウィンドウでファイルを開く処理。タブ結合の基準にするため自分のウィンドウも渡す。
    /// 本番では ViewerWindowManager 経由で注入する。
    private let openFileElsewhere: (URL, OpenDisposition, NSWindow?) -> Void
    /// 外部 URL(http/https)をブラウザで開く処理。本番では NSWorkspace 経由。
    /// テストが実ブラウザを起動せずに済むよう注入可能にしている。
    private let externalOpener: (URL) -> Void
    /// 生成した SplitViewController への型消去参照。contentViewController が保持するため weak。
    /// CLI の `--sidebar`/`--no-sidebar` を既存ウィンドウへ適用する際に使う。
    private weak var sidebarCollapsible: (any SidebarCollapsible)?
    /// 二本指スワイプによるファイル履歴ナビゲーション検知。ウィンドウ生成後に start()、
    /// 閉じるときに stop() する。
    private var swipeMonitor: SwipeHistoryMonitor!
    /// ツールバー(モード切替・戻る/進む・行番号)の構築とライブ状態更新を担う。
    private(set) var toolbarController: ViewerToolbarController!
    private let webViewProxy = WebViewProxy()
    /// WebView 操作系メニューアクション(ズーム・印刷・検索・スクロール位置保存)の実処理。
    private var webViewCommands: WebViewCommandController!
    /// ソース表示モードの唯一の真実の源は store。二重保持を避けるため委譲する。
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
    private let gitFileIndex: any GitFileIndexing
    /// パス参照の解決(索引の先読み・クリック時のオープン・表示時の一括解決)を担う。
    /// fileReader は store と共有する(既存の fileExists/isExistingFile 共有と同じ理由で
    /// InMemoryFileReader 注入テストと整合させる)。
    lazy var referenceCoordinator = ReferenceResolutionCoordinator(
        host: self, fileReader: store.fileReader, gitIndex: gitFileIndex
    )

    // MARK: - Initialization

    /// - Parameter sidebarDisplayPreference: 本番では必ず AppDelegate → ViewerWindowManager から
    ///   注入される単一の共有インスタンスを渡すこと。デフォルト値は、不可視ファイル挙動に
    ///   無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    /// - Parameter perFileState: 同上。ファイル毎の永続表示状態(倍率・ソース表示モード・
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
    /// - Parameter openFileElsewhere: 同上。別タブ/別ウィンドウでのオープン先。デフォルトは AppDelegate 経由。
    /// - Parameter externalOpener: 同上。外部 URL(http/https)を開く処理。デフォルトは NSWorkspace 経由。
    init(
        fileURL: URL, defaults: UserDefaults = .standard,
        sidebarDisplayPreference: SidebarDisplayPreference = SidebarDisplayPreference(),
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
        openFileElsewhere: @escaping (URL, OpenDisposition, NSWindow?) -> Void = { url, disposition, source in
            AppDelegate.shared?.openViewer(for: url, disposition: disposition, relativeTo: source)
        },
        externalOpener: @escaping (URL) -> Void = { url in NSWorkspace.shared.open(url) }
    ) {
        initialFileURL = fileURL
        self.perFileState = perFileState
        self.defaults = defaults
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.findOptionsPreference = findOptionsPreference
        self.codeFontPreference = codeFontPreference
        self.bookmarkStore = bookmarkStore
        self.gitFileIndex = gitFileIndex
        self.initialSidebarCollapsed = initialSidebarCollapsed
        let store = store ?? ViewerStore(defaults: defaults)
        // store が呼び出し元から明示注入された場合でも上書きが反映されるよう、
        // store の生成元にかかわらずここで一律に適用する(sourceModeOverride と同じ方針)。
        if let showLineNumbersOverride {
            store.applyShowLineNumbersOverride(showLineNumbersOverride)
        }
        self.store = store
        self.openFileElsewhere = openFileElsewhere
        self.externalOpener = externalOpener
        let parentDir = fileURL.deletingLastPathComponent()
        // 初期一覧は空で始め、attach 直後の refreshFileList()(非同期の DirectoryLister.listEntriesAsync)に
        // 埋めさせる。ウィンドウ生成時だけ同期列挙する経路を持たないことで、ネットワーク
        // ボリューム上のフォルダでもウィンドウ表示がディレクトリ列挙を待たない。
        sidebar = SidebarNavigator(
            currentDirectory: parentDir, entries: [], selection: fileURL,
            sidebarDisplayPreference: sidebarDisplayPreference, sortOrder: initialSortOrder,
            // 未命中時は `git rev-parse` の subprocess を同期で待つため、
            // メインアクターを離して解決する(サイドバーのヘッダー表示のためだけに
            // フォルダ移動のたびメインスレッドを止めないため)。
            resolveGitRoot: { [gitFileIndex] directory in
                await Task.detached { gitFileIndex.repositoryRoot(forDirectoryAt: directory) }.value
            },
            loadGitStatuses: makeSidebarGitStatusLoader(gitStatusStore)
        )

        // ウィンドウの実サイズは contentViewController 設定後に確定させるため、
        // ここでの contentRect はプレースホルダ
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 400, height: 300)
        // コンテンツの地の色はウィンドウ背景が唯一の定義(ViewerTheme.canvas)。
        // WebView は透過(drawsBackground=false)のためこの色が透けて見える
        window.backgroundColor = ViewerTheme.canvas
        // 標準タイトルバーは背景色の上にマテリアルを重ねるため、背景色を
        // 揃えてもわずかに明るく描かれる。透過させて背景色を直接見せ、
        // 区切り線も消してコンテンツと完全に地続きにする
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.title = fileURL.lastPathComponent
        // タイトルバーにプロキシアイコンを表示し、Cmd+クリックのパス表示・
        // タイトルバーからのドラッグを有効にする
        window.representedURL = fileURL
        window.tabbingIdentifier = "ViewerWindow"
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbarStyle = .unified

        super.init(window: window)

        // toolbarController は self(ViewerToolbarHost) を使うため super.init の後に生成する。
        // window.toolbar もデリゲート設定後に代入しないとアイテムが空になる。
        toolbarController = ViewerToolbarController(window: window, host: self)
        toolbar.delegate = toolbarController
        window.toolbar = toolbar

        webViewCommands = WebViewCommandController(
            // WKWebView と JS の詳細は adapter に閉じる(ADR 0002 段 4)。
            renderer: WebViewDocumentRenderer(webViewProxy: webViewProxy),
            perFileState: perFileState,
            // 現在 URL は rename/switch で書き換わるため、旧値を捕捉せず self 経由で参照する。
            currentURL: { [weak self] in self?.fileURL ?? fileURL },
            // 実行可否は capabilities に集約する(ADR 0002)。フォルダー一覧を表示している間も
            // WKWebView は背後に生き続けるため、見えていない文書への操作はここで止まる。
            capabilities: { [weak self] in self?.capabilities ?? .none }
        )

        // contentViewController の設定でウィンドウがビューのフィッティングサイズに
        // リサイズされるため、フレームの確定はその後に行う。
        // frameDescriptor はフレーム座標系で保存・復元されるため、
        // タイトルバー高さの混入によるサイズのずれは起きない
        window.contentViewController = makeSplitViewController(contentOverride: makeContentView)
        if let descriptor = initialFrameDescriptor {
            window.setFrame(from: descriptor)
            // 自身の保存値・引き継ぎ値のどちらでも、既存ウィンドウと位置が
            // 完全に一致する場合は重なって見分けが付かなくなるためずらす。
            offsetFrameToAvoidOverlap(window)
        } else {
            window.setContentSize(Self.defaultContentSize)
            window.center()
        }

        // delegate の設定はフレーム確定後にする。init 中のリサイズ
        // (contentViewController 設定によるフィッティングサイズ化など)が
        // windowDidResize 経由で保存されるのを防ぐ
        window.delegate = self

        swipeMonitor = SwipeHistoryMonitor(window: window) { [weak self] offset in
            self?.navigateHistory(by: offset)
        }
        swipeMonitor.start()

        // ツールバーの view ベースアイテムは validate を通らないため、提示対象が
        // 変わったら明示的に再同期する(ADR 0002)。フォルダー一覧へ切り替わったときは
        // キー入力の宛先も一覧へ移す(背後の見えない文書がキーを受け取り続けるのを防ぐ)。
        fileListModel.onPresentationTargetChange = { [weak self] in
            guard let self else { return }
            refreshToolbarState()
            if isPreviewingFolder { fileListModel.focusSidebarTable() }
        }
        sidebar.attach(to: self)
        // 空で作ったサイドバー一覧をここで埋める(列挙はメインアクター外で走る)。
        sidebar.refreshFileList()
        wireStoreCallbacks()
        store.openFile(fileURL)
        // クリック時解決(pathResolver)の git 追跡ファイル索引を先読みしておく。
        referenceCoordinator.warm(forFileAt: fileURL)
        // 直接開いた場合も、切替(performFileSwitch)と同じく保存済みのソース表示モードを復元する。
        // CLI から --source/--preview が指定された場合はそちらを優先し、保存値は書き換えない(この起動限りの上書き)。
        // applySourceMode が内部で refreshToolbarState() を呼ぶため、ここでの明示呼び出しは不要。
        applySourceMode(sourceModeOverride ?? perFileState.sourceMode.restoredSourceMode(for: fileURL))
        sidebar.recordHistory()
    }

    /// サイドバー(ファイル一覧)とコンテンツ(WebView/フォルダー一覧)を並べる split view controller を組み立てる。
    private func makeSplitViewController(contentOverride: (() -> AnyView)?) -> NSViewController {
        let onSelectFile: (URL) -> Void = { [weak self] url in self?.switchFile(to: url) }
        let onNavigateToFolder: (URL) -> Void = { [weak self] url in self?.navigateToFolder(url) }
        let content: AnyView = contentOverride?() ?? AnyView(ViewerContentView(
            store: store,
            zoomStore: perFileState.zoom,
            scrollPositionStore: perFileState.scrollPosition,
            findOptionsPreference: findOptionsPreference,
            codeFontFamily: codeFontPreference.fontFamily,
            codeFontSizePoints: codeFontPreference.fontSizePoints,
            fileListModel: fileListModel,
            rendererDelegate: WeakRendererDelegate(self),
            onSelectFile: onSelectFile,
            onNavigateToFolder: onNavigateToFolder,
            webViewProxy: webViewProxy
        ))
        let fileListView = FileListView(
            model: fileListModel,
            onSelect: onSelectFile,
            onNavigate: onNavigateToFolder,
            onSortOrderChanged: { [weak self] order in
                guard let self else { return }
                fileListModel.sortOrder = order
                sidebar.refreshFileList()
            },
            onOpenInNewWindow: { [weak self] url in
                guard let self else { return }
                openFileElsewhere(url, .newWindow, window)
            },
            onToggleHiddenFiles: { [weak self] in
                guard let self else { return }
                delegate?.viewerWindowDidToggleHiddenFiles(self)
            },
            onToggleChangedFilesOnly: makeChangedFilesOnlyToggle()
        )
        let splitViewController = ViewerSplitViewController(
            sidebar: fileListView,
            content: content,
            initialCollapsed: initialSidebarCollapsed,
            onCollapsedChange: { [weak self] collapsed in
                guard let self else { return }
                perFileState.sidebar.recordToggle(collapsed, for: fileURL)
            },
            onSidebarDidReveal: { [weak self] in
                self?.fileListModel.focusSidebarTable()
            }
        )
        sidebarCollapsible = splitViewController
        return splitViewController
    }

    /// サイドバーヘッダーの「変更されたファイルのみ表示」ボタンの動作を作る。
    ///
    /// git ステータスと同じ開発中機能の露出点であり、無効なら nil を返して
    /// ボタン自体を出さない(FileListView 側が nil で非表示にする)。
    private func makeChangedFilesOnlyToggle() -> (() -> Void)? {
        guard FeatureGate.inProgressFeaturesEnabled else { return nil }
        return { [weak self] in
            guard let self else { return }
            delegate?.viewerWindowDidToggleChangedFilesOnly(self)
        }
    }

    /// CLI の `--sidebar`/`--no-sidebar` から、この既存ウィンドウのサイドバー開閉を設定する。
    func setSidebarCollapsed(_ collapsed: Bool) {
        sidebarCollapsible?.setSidebarCollapsed(collapsed)
    }

    /// リンク/パス参照のアクティベーションを処理する。
    /// テスト(@testable import)から回帰テストとして直接呼べるよう internal にする（外部公開はしない）。
    func handleOpenReference(href: String, disposition: OpenDisposition) {
        referenceCoordinator.handleOpenReference(href: href, disposition: disposition)
    }

    /// パス参照群を解決し、実在するものだけ「書かれたパス→解決済み絶対パス」で返す(表示時解決用)。
    func resolveReferences(_ paths: [String]) async -> [String: String] {
        await referenceCoordinator.resolveReferences(paths)
    }

    /// ファイルの rename / move をウィンドウに反映する。
    /// リネームは同一ファイルの改名であり、内容・表示倍率・ビューモードは原則保持する。
    func handleRename(from oldURL: URL, to newURL: URL) {
        guard newURL.normalizedPathKey != oldURL.normalizedPathKey else { return }
        applyURLToWindow(newURL)

        // 実体は同じファイルなので旧パスの表示状態(倍率・ソース表示モード・スクロール位置)を
        // 新パスへまとめて引き継ぐ(旧パスはもう存在しない)。
        perFileState.migrate(from: oldURL, to: newURL)
        // 内容は不変なのでビューモードは維持する。ただし対応形式が変わり
        // (例: .md → .swift、.md → .png)ソース表示トグルが成立しなくなる
        // 場合のみリセットする。
        // store.handleRename が予約した非同期読み込みの完了後に onContentReloaded が
        // 発火してツールバーが追従するため、ここでの明示的な
        // refreshToolbarState() 呼び出しは不要
        // (resetSourceMode() が走る場合は applySourceMode 内で再同期される)。
        if isSourceMode, !FileType(url: newURL).supportsSourceMode {
            resetSourceMode()
        }
        let newDir = newURL.deletingLastPathComponent()
        if newDir.normalizedPathKey
            != fileListModel.currentDirectory.normalizedPathKey
        {
            fileListModel.currentDirectory = newDir
        }
        sidebar.refreshFileList()
        delegate?.viewerWindow(self, didRenameFrom: oldURL, to: newURL)
        sidebar.applyRename(from: oldURL, to: newURL)
    }

    /// サイドバーで別ファイルが選択されたときにウィンドウの表示対象を切り替える。
    /// ファイル切替の実処理のみ担い、選択同期・履歴記録は SidebarNavigator へ委譲する。
    func switchFile(to newURL: URL) {
        let oldURL = fileURL
        guard newURL.normalizedPathKey != oldURL.normalizedPathKey else { return }
        referenceCoordinator.warm(forFileAt: newURL)
        switch performFileSwitch(to: newURL) {
        case .switched:
            sidebar.syncAfterSwitch(to: newURL)
        case .failed:
            sidebar.restoreSelection(to: oldURL)
        }
    }

    /// このウィンドウをキーウィンドウにして前面へ出す。
    func focusWindow() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// サイドバーで別フォルダーへ移動する。詳細は SidebarNavigator に委譲する。
    func navigateToFolder(_ url: URL) {
        sidebar.navigateToFolder(url)
    }

    /// サイドバーの戻る/進む・履歴メニューから呼ばれる。offset 負=戻る / 正=進む。
    func navigateHistory(by offset: Int) {
        sidebar.navigateHistory(by: offset)
    }

    /// switchFile と履歴適用が共有するファイル切替の実処理。
    /// 切替先ファイルの保存済みビューモードの復元、URL 更新、コンテンツ読込、
    /// ズーム適用、コールバック通知を行う。
    /// 操作中(アクティブ)のウィンドウを最優先するため、切替先が別ウィンドウで開いていても
    /// そのまま自ウィンドウを切り替える(他ウィンドウの前面化はしない)。存在しない場合のみ
    /// 状態を変更せず .failed を返し、アラートを表示する。
    @discardableResult
    func performFileSwitch(to newURL: URL) -> FileSwitchOutcome {
        guard store.fileExists(at: newURL) else {
            presentReferenceNotFound(url: newURL)
            return .failed
        }
        let oldURL = fileURL
        saveScrollPositionBeforeTransition()
        let restoredSourceMode = perFileState.sourceMode.restoredSourceMode(for: newURL)
        applySourceMode(restoredSourceMode)
        applyURLToWindow(newURL)
        // fileExists を確認済みなので store.openFile が予約した非同期読み込みは必ず完了に達し、
        // その時点で onContentReloaded → refreshToolbarState() が発火する
        // (読み込み完了までは切替前の表示状態が残る)。ここでの明示呼び出しは不要。
        store.openFile(newURL)
        webViewCommands.applyStoredZoom()
        delegate?.viewerWindow(self, didSwitchFileFrom: oldURL, to: newURL)
        return .switched
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - Window / Content Helpers

extension ViewerWindowController {
    /// ウィンドウのタイトルと representedURL を新しい URL に合わせて更新する。
    /// handleRename / switchFile 共通の表示更新。現在 URL 自体は store が保持するため
    /// ここでは複製・代入せず、ウィンドウの見た目だけを追従させる。
    private func applyURLToWindow(_ newURL: URL) {
        guard let window else { return }
        window.title = newURL.lastPathComponent
        window.representedURL = newURL
    }

    /// 既存のビューアウィンドウと位置が完全に一致する場合だけ、標準のカスケード量ずらす。
    /// cascadeTopLeft(from:) は移動先を戻り値で返すため、戻り値を自分に適用する。
    /// ずらした先が別ウィンドウと一致することがあるので、重ならなくなるまで繰り返す。
    private func offsetFrameToAvoidOverlap(_ window: NSWindow) {
        func overlapsExisting() -> Bool {
            NSApp.windows.contains { other in
                other !== window
                    && other.isVisible
                    && other.windowController is ViewerWindowController
                    && other.frame.origin == window.frame.origin
            }
        }
        var attempts = 0
        while overlapsExisting(), attempts < 20 {
            let shifted = window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
            window.setFrameTopLeftPoint(shifted)
            attempts += 1
        }
    }
}

// MARK: - SidebarNavigatorHost

extension ViewerWindowController: SidebarNavigatorHost {
    /// SidebarNavigator が現在ファイルを都度参照するための橋渡し。
    var currentFileURL: URL {
        fileURL
    }

    /// 履歴状態の変化をツールバーへ反映する。
    func historyStateDidChange() {
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

// MARK: - ViewerRendererDelegate

extension ViewerWindowController: ViewerRendererDelegate {
    /// 現在の fileURL は rename で書き換わるため、旧値を捕捉せず呼び出しのたびに参照する。
    func renderer(_: ViewerRenderer, didChangeZoom zoom: Double) {
        perFileState.zoom.setZoom(zoom, for: fileURL)
    }

    func renderer(
        _: ViewerRenderer, didChangeScrollPosition position: Double, mode: ViewerBridge.ViewMode
    ) {
        perFileState.scrollPosition.setScrollPosition(position, for: fileURL, mode: mode)
    }

    func renderer(_: ViewerRenderer, didActivateReference href: String, disposition: OpenDisposition) {
        handleOpenReference(href: href, disposition: disposition)
    }

    func renderer(_: ViewerRenderer, didRequestContextMenuFor href: String) {
        referenceCoordinator.handleContextMenu(href: href)
    }

    func renderer(_: ViewerRenderer, resolveReferences paths: [String]) async -> [String: String] {
        await resolveReferences(paths)
    }

    func rendererDidRequestMoreLines(_: ViewerRenderer) async -> LoadMoreLinesResult? {
        await store.loadMoreLines()
    }
}

// MARK: - ReferenceResolutionHost

extension ViewerWindowController: ReferenceResolutionHost {
    /// ReferenceResolutionCoordinator が解決の基準ディレクトリを都度参照するための橋渡し。
    var referenceBaseURL: URL {
        fileURL
    }

    /// 解決できたパス参照を、開き方(disposition)に応じてこのウィンドウ/別タブ/別ウィンドウで開く。
    func openReference(_ url: URL, disposition: OpenDisposition) {
        switch disposition {
        case .currentTab:
            switchFile(to: url)
        case .newTab, .newWindow:
            openFileElsewhere(url, disposition, window)
        }
    }

    /// 参照先が見つからないことをユーザーに知らせる。
    /// window があればシート、無ければモーダルで表示する(判定は FileNotFoundUI 側)。
    func presentReferenceNotFound(url: URL) {
        FileNotFoundUI.present(url: url, over: window)
    }

    /// リンク/パス参照の ctrl+クリック(右クリック)で NSMenu を表示する。
    /// 表示位置は JS の座標ではなく現在のマウス位置を使う(WKWebView の CSS ピクセルと
    /// NSView 座標の変換、ページズームの影響を避けるため)。
    func presentReferenceContextMenu(for url: URL, isExternal: Bool) {
        guard let contentView = window?.contentView,
              let location = window?.mouseLocationOutsideOfEventStream
        else { return }
        let menu = ReferenceContextMenu.makeMenu(
            for: url, isExternal: isExternal, target: self, action: #selector(performReferenceMenuAction(_:))
        )
        menu.popUp(positioning: nil, at: contentView.convert(location, from: nil), in: contentView)
    }

    /// コンテキストメニューの各項目の実行を、既存の遷移・Finder・クリップボード処理へ委譲する。
    @objc private func performReferenceMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? ReferenceMenuInvocation else { return }
        switch invocation.action {
        case let .open(disposition):
            // 外部 URL(http/https)はファイルビューア経路(switchFile/openFileElsewhere)に
            // ローカルパスが無く、渡すと「ファイルが見つかりません」になる。修飾キーに
            // かかわらずブラウザで開く(通常クリック・cmd+クリックと同じ扱いに揃える)。
            if invocation.isExternal {
                externalOpener(invocation.url)
            } else {
                openReference(invocation.url, disposition: disposition)
            }
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([invocation.url])
        case .copyName:
            writeToPasteboard(invocation.url.lastPathComponent)
        case .copyRelativePath:
            writeToPasteboard(PathRelativizer.relativePath(of: invocation.url, relativeTo: referenceBaseURL))
        }
    }

    /// NSPasteboard.general へ文字列を書き込む(FileListView の copyPath と同じ処理)。
    private func writeToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

// MARK: - ViewerToolbarHost

extension ViewerWindowController: ViewerToolbarHost {}

// MARK: - Source Mode

extension ViewerWindowController {
    /// 表示中ファイル・表示モードを書き換える前に、退場側(現在の URL・現在のモード)の
    /// スクロール位置を明示的なキーで確定保存する。
    ///
    /// 切替後に保存すると、退場側の位置が入場側ファイル・入場側モードのキーへ誤って
    /// 保存されるため、必ず書き換え前に呼ぶこと。この save-before-mutate の順序制約を
    /// 負う入口はここだけで、呼び出し点はファイル切替(performFileSwitch)と
    /// モード切替(setSourceMode)の 2 つ。
    private func saveScrollPositionBeforeTransition() {
        webViewCommands.saveCurrentScrollPosition(
            for: fileURL, mode: ViewerBridge.ViewMode(isSourceMode: isSourceMode)
        )
    }

    /// isSourceMode を変更し、store・永続化・モード切替セグメントの表示更新までを一貫して行う。
    /// ツールバーのモード切替セグメント(ViewerToolbarController)からも ViewerToolbarHost 経由で呼ばれる。
    func setSourceMode(_ newValue: Bool) {
        // validate を通らない経路(ツールバーのセグメント・オーバーフローメニュー)も
        // ここへ来るため、能力の確認は実行側にも置く(ADR 0002)。
        guard capabilities.canToggleSourceMode else { return }
        if newValue != isSourceMode {
            saveScrollPositionBeforeTransition()
        }
        applySourceMode(newValue)
        perFileState.sourceMode.setSourceMode(isSourceMode, for: fileURL)
    }

    /// isSourceMode を変更し、store への反映とツールバーの表示更新までを一貫して行う。
    /// 永続化を伴わない復元・強制リセット(init・performFileSwitch・resetSourceMode)は
    /// 保存値を書き換えないためこちらを使う。
    /// isSourceMode の変更が store 経由で SwiftUI の更新サイクルをトリガーし、
    /// ViewerWebView.updateNSView → updateContent が呼ばれ、
    /// 自動的にモード切替(必要なら再描画)が行われる。
    private func applySourceMode(_ newValue: Bool) {
        if isSourceMode != newValue {
            store.isSourceMode = newValue
        }
        refreshToolbarState()
    }

    /// リネームで表示形式がソース表示非対応になったとき、レンダリング表示へ戻す。
    /// 保存値は残す(リネーム時のキー付け替えは PerFileStateStore.migrate が行う)。
    private func resetSourceMode() {
        applySourceMode(false)
    }

    /// ソース表示トグルを有効にできるか。レンダリング可能な形式でも、
    /// サイズ超過などで非対応表示になっている間は切り替え先が不可視なため無効にする。
    var canToggleSourceMode: Bool {
        store.fileType.supportsSourceMode && !store.isRejected
    }
}

// MARK: - Presentation State / Capabilities

extension ViewerWindowController {
    /// プレビュー領域がフォルダー一覧を出しているか。ViewerContentView と同じ
    /// fileListModel.previewTarget を見る(導出点は 1 つ。ADR 0002)。
    var isPreviewingFolder: Bool {
        fileListModel.previewTarget.folderURL != nil
    }

    /// いま何ができるか。メニュー・ツールバー・コマンド実行はすべてこの値だけを見る(ADR 0002)。
    /// 条件をここ以外に書かないことで、「メニューは無効なのに別経路では通る」を作らない。
    var capabilities: ViewerCapabilities {
        ViewerCapabilities(
            isPresentingDocument: !isPreviewingFolder,
            isRejected: store.isRejected,
            isRenderable: store.fileType.isRenderable,
            isBinaryContent: store.fileType.isBinaryContent,
            showsCodeContent: store.showsCodeContent,
            supportsSourceMode: store.fileType.supportsSourceMode,
            isDirectHTMLMode: webViewProxy.isDirectHTMLMode
        )
    }
}

// MARK: - Menu Actions / Validation / NSWindowDelegate

extension ViewerWindowController: NSWindowDelegate {
    /// 現在のウィンドウフレーム（位置＋サイズ）を保存する。
    /// フルスクリーン中のフレームは通常ウィンドウの寸法として無意味なため保存しない。
    private func saveWindowFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        perFileState.windowFrame.recordUserAdjustedFrame(window.frameDescriptor, for: fileURL)
    }

    /// View > Zoom In。HTML 直接ロード時は WKWebView の pageZoom を、それ以外は JS ズーム実装を使う。
    @objc func zoomIn(_ sender: Any?) {
        webViewCommands.zoomIn()
    }

    /// View > Zoom Out。
    @objc func zoomOut(_ sender: Any?) {
        webViewCommands.zoomOut()
    }

    /// View > Actual Size。倍率を 100% に戻す。
    @objc func resetZoom(_ sender: Any?) {
        webViewCommands.resetZoom()
    }

    /// File > Print…。WebView の描画内容を印刷する。
    @objc func printDocument(_ sender: Any?) {
        webViewCommands.printDocument(over: window)
    }

    /// Edit > 検索…。プレビュー右上の検索バーを開く。
    /// HTML ファイルの直接ロード表示中は viewer.html の JS が存在しないため無効化する
    /// (validateMenuItem 側で判定)。
    @objc func find(_ sender: Any?) {
        webViewCommands.openFind()
    }

    /// Edit > 次を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findNext(_ sender: Any?) {
        webViewCommands.findNext()
    }

    /// Edit > 前を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findPrevious(_ sender: Any?) {
        webViewCommands.findPrevious()
    }

    /// View > Toggle Line Numbers / ツールバーの行番号ボタン。行番号表示の有無を切り替える。
    @objc func toggleLineNumbers(_ sender: Any?) {
        guard capabilities.canToggleLineNumbers else { return }
        store.showLineNumbers.toggle()
        refreshToolbarState()
    }

    /// View メニュー > ソース表示トグル。レンダリング表示とソース表示を切り替える。
    @objc func toggleSourceView(_ sender: Any?) {
        setSourceMode(!isSourceMode)
    }

    /// View > Bookmark / ツールバーのブックマークボタン。現在ファイルのブックマーク状態を切り替える。
    @objc func toggleBookmark(_ sender: Any?) {
        guard capabilities.canBookmark else { return }
        bookmarkStore.toggle(fileURL)
        refreshToolbarState()
    }

    /// 現在ファイルがブックマーク済みかどうか。ツールバー・View メニューの表示に使う。
    var isBookmarked: Bool {
        bookmarkStore.isBookmarked(fileURL)
    }

    /// View > Back。ファイル履歴を 1 つ戻る。
    @objc func goBack(_ sender: Any?) {
        navigateHistory(by: -1)
    }

    /// View > Forward。ファイル履歴を 1 つ進む。
    @objc func goForward(_ sender: Any?) {
        navigateHistory(by: 1)
    }

    /// 有効判定は capabilities(提示状態からの導出)だけを見る。ここでの分岐は
    /// 「どのセレクタがどの能力に対応するか」の対応表であって、条件そのものは書かない(ADR 0002)。
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSourceView(_:)) {
            menuItem.title = ViewerCommandTitles.sourceView(isSourceMode: isSourceMode)
            return capabilities.canToggleSourceMode
        }
        if menuItem.action == #selector(toggleLineNumbers(_:)) {
            menuItem.title = ViewerCommandTitles.lineNumbers(isShown: store.showLineNumbers)
            return capabilities.canToggleLineNumbers
        }
        if menuItem.action == #selector(toggleBookmark(_:)) {
            menuItem.title = ViewerCommandTitles.bookmark(isBookmarked: isBookmarked)
            return capabilities.canBookmark
        }
        if menuItem.action == #selector(goBack(_:)) {
            return fileListModel.canGoBack
        }
        if menuItem.action == #selector(goForward(_:)) {
            return fileListModel.canGoForward
        }
        let findActions: [Selector] = [#selector(find(_:)), #selector(findNext(_:)), #selector(findPrevious(_:))]
        if let action = menuItem.action, findActions.contains(action) {
            return capabilities.canFind
        }
        if menuItem.action == #selector(printDocument(_:)) {
            return capabilities.canPrint
        }
        let zoomActions: [Selector] = [#selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(resetZoom(_:))]
        if let action = menuItem.action, zoomActions.contains(action) {
            return capabilities.canZoom
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        swipeMonitor.stop()
        saveWindowFrame()
        store.close()
        sidebar.cancelPendingListing()
        delegate?.viewerWindowWillClose(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // ディレクトリ監視はしていないため、キーになったタイミングで一覧を取り直し、
        // 他所で作成/削除されたファイルをサイドバーへ反映する。
        sidebar.refreshFileList()
        delegate?.viewerWindowDidBecomeKey(self)
    }

    /// リサイズ完了時にのみ保存する。ライブリサイズ中は windowDidResize が毎フレーム
    /// 飛ぶため、そこでは保存せず UserDefaults への連打を避ける。
    /// ドラッグ移動やタイリングでの位置変更は windowWillClose 時にまとめて保存される。
    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrame()
    }
}

// MARK: - ViewerStore Callbacks

private extension ViewerWindowController {
    /// ViewerStore からの通知(ファイル消失・rename・再読込)をウィンドウ側の処理へ繋ぐ。
    ///
    /// クラス本体ではなく extension に置くのは、init を読むときに「何を購読するか」が
    /// 1 行(`wireStoreCallbacks()`)に畳まれ、購読内容の追加でウィンドウ生成手順の
    /// 見通しが悪くならないようにするため。
    func wireStoreCallbacks() {
        store.onFileGone = { [weak self] in
            self?.window?.close()
        }
        store.onFileRenamed = { [weak self] oldURL, newURL in
            self?.handleRename(from: oldURL, to: newURL)
        }
        store.onContentReloaded = { [weak self] in
            self?.refreshToolbarState()
            // 表示中ファイルの保存に git バッジを追従させる。作業ツリーの編集は
            // `.git/index` を動かさないため index 監視では拾えず、ここが唯一の契機になる。
            // 再読込は FileWatcher のデバウンス後に 1 回来るので、連打にはならない。
            self?.sidebar.refreshGitStatuses()
        }
    }
}
