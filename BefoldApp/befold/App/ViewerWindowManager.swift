import AppKit
import BefoldCLI
import BefoldKit
import SwiftUI

/// ビューアウィンドウの生成・管理(正規化パス → コントローラ辞書)と、
/// ウィンドウイベント(クローズ・rename・キー化)に伴うセッション記録の更新を担う。
@MainActor
final class ViewerWindowManager {
    /// 正規化パス → そのファイルを表示中のコントローラ群。
    /// 操作中(アクティブ)のウィンドウのサイドバー切替を最優先するため、同一ファイルを
    /// 複数ウィンドウで開くことを許す(1 対 1 ではない)。Finder/CLI からの再オープンは
    /// 依然として既存ウィンドウを前面化して重複を作らないが、ウィンドウ内のファイル切替では
    /// 他ウィンドウの有無に関わらず自ウィンドウを切り替える。
    private(set) var controllers: [String: [ViewerWindowController]] = [:]

    /// 開いている全コントローラ(同一ファイルの重複ウィンドウも含む)。
    /// 全ウィンドウへの一括反映(サイドバー・ツールバー再同期など)はこれを走査する。
    var allControllers: [ViewerWindowController] {
        controllers.values.flatMap(\.self)
    }

    private let sessionStore: SessionStore
    private let recentDocumentsStore: RecentDocumentsStore
    private let sidebarDisplayPreference: SidebarDisplayPreference
    /// 全ウィンドウで共有する差分表示設定。ここで 1 つ持って openViewer で渡すことが、
    /// 「粒度はアプリ全体」(DiffDisplayPreference の doc コメント)を成立させている。
    private let diffDisplayPreference: DiffDisplayPreference
    /// 全ウィンドウで共有する差分の取得元。ここで 1 つ持つことが、GitDiffLoader の
    /// 「同じ要求が重なったら git を二重起動しない」を窓をまたいで成立させている。
    /// 窓ごとに持つと、同じファイルを 2 窓で開いた状態の 1 回の保存で
    /// `git diff` が窓の数だけ起動する(TASK-325)。
    /// 機能ゲートが無効なビルドでは nil で、git diff を一切実行しない。
    let diffLoader: GitDiffLoader?
    private let findOptionsPreference: FindOptionsPreference
    private let codeFontPreference: CodeFontPreference
    private let perFileState: PerFileStateStore
    private let bookmarkStore: BookmarkStore
    /// openViewer のファイル存在ガードが使う I/O 抽象。静的な DefaultFileReader を直接叩かず
    /// ここへ集約することで、テストが InMemoryFileReader を注入して存在確認をモック化できる。
    private let fileReader: any FileReading
    /// openViewer が生成するコントローラへ渡す ViewerStore の差し替え口。nil なら
    /// ViewerWindowController が従来どおり自前で生成する(本番の既定)。
    private let makeStore: ((URL) -> ViewerStore)?
    /// openViewer が生成するコントローラへ渡すコンテンツペインの差し替え口。nil なら
    /// ViewerWindowController が従来どおり実 ViewerContentView(実 WKWebView)を生成する(本番の既定)。
    private let makeContentView: (() -> AnyView)?
    /// 生成する全ウィンドウで共有する git 追跡ファイルの索引。同じリポジトリのファイルを
    /// 全ウィンドウ・Quick Open で共有する追跡ファイル索引。複数ウィンドウで開いても
    /// `git ls-files` は 1 回で済み、照合索引の実体も 1 つで済む(モノレポでは
    /// ウィンドウごとの複製が無視できない大きさになる)。ウィンドウが温めた同じ
    /// インスタンスを Quick Open の候補源もそのまま使う。
    let gitFileIndex: any GitFileIndexing
    /// サイドバーの git 状態バッジの取得元。全ウィンドウで 1 個を共有し、同じリポジトリを
    /// 開いた複数ウィンドウで `git status` の実行とキャッシュをまとめる。
    /// 既定は無効化状態(常に空)で、本番のルート解決付きインスタンスは AppDelegate が差し込む。
    var gitStatusStore = GitStatusStore()
    /// 「最近使ったリポジトリ」の記録先。git ルートを持つファイルを開いた際に record、
    /// そのウィンドウが閉じるたび・アプリ終了時に updateLastTabGroup でタブ構成を更新する。
    private let recentRepositoriesStore: RecentRepositoriesStore
    /// root からメニュー表示用ラベルと本体リポジトリのルートを解決する。既定は実 GitRepository。
    /// 解決は MainActor の外(detached タスク)で走るため @Sendable が要る。
    /// テストは実 git を起動しないフェイクへ差し替える。
    private let repositoryIdentityResolver: @Sendable (URL) -> RepositoryIdentity
    /// 「最近使ったリポジトリ」へ新しい本体ルートを記録した直後に呼ばれる。
    /// AppDelegate が WorktreeCatalog を追随させるために使う。
    private let onRepositoryRecorded: (URL) -> Void

    /// - Parameter sidebarDisplayPreference: 本番では必ず AppDelegate が持つ単一の共有インスタンスを渡すこと。
    ///   デフォルト値は、不可視ファイル挙動に無関心なテストが省略できるようにするためのもの。
    /// - Parameter diffDisplayPreference: 差分レイアウトは全ウィンドウで同じ答えになる必要があるため、
    ///   ここで受けた 1 つを openViewer が全コントローラへ渡す。既定値を持たせないのは、
    ///   渡し忘れが静かに別インスタンスになるのを防ぐため（TASK-319）。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    /// - Parameter perFileState: 同上。ファイル毎の永続表示状態(倍率・表示モード・
    ///   スクロール位置)の束。これらの挙動に無関心なテストが省略できるようにする。
    /// - Parameter bookmarkStore: 同上。ブックマーク挙動に無関心なテストが省略できるようにする。
    /// - Parameter makeStore: 生成するコントローラの ViewerStore を差し替える。既定の nil では
    ///   コントローラが自前で生成するため本番挙動は変わらない。テストが実 FileWatcher と
    ///   実ファイル読込を避けて生成パイプラインごと unit 化するための唯一のシーム。
    /// - Parameter makeContentView: テスト専用シーム。生成するコントローラのコンテンツペイン
    ///   (実 WKWebView)を差し替える。既定の nil は本番経路(実 WKWebView を生成する)。
    /// - Parameter gitFileIndex: 生成する全ウィンドウで共有する git 追跡ファイルの索引。
    ///   既定は実 `git` を実行する実装。テストは実 subprocess を避けるため差し替えられる。
    init(
        sessionStore: SessionStore, recentDocumentsStore: RecentDocumentsStore,
        sidebarDisplayPreference: SidebarDisplayPreference = SidebarDisplayPreference(),
        diffDisplayPreference: DiffDisplayPreference,
        diffLoader: GitDiffLoader? = ViewerWindowManager.makeDiffLoader(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        codeFontPreference: CodeFontPreference = CodeFontPreference(),
        perFileState: PerFileStateStore = PerFileStateStore(),
        bookmarkStore: BookmarkStore,
        fileReader: any FileReading = DefaultFileReader(),
        makeStore: ((URL) -> ViewerStore)? = nil,
        makeContentView: (() -> AnyView)? = nil,
        gitFileIndex: any GitFileIndexing = GitCommandFileIndex(),
        recentRepositoriesStore: RecentRepositoriesStore = RecentRepositoriesStore(),
        repositoryIdentityResolver: @escaping @Sendable (URL) -> RepositoryIdentity = {
            GitRepository().repositoryIdentity(forRoot: $0)
        },
        onRepositoryRecorded: @escaping (URL) -> Void = { _ in }
    ) {
        self.gitFileIndex = gitFileIndex
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.diffDisplayPreference = diffDisplayPreference
        self.diffLoader = diffLoader
        self.findOptionsPreference = findOptionsPreference
        self.codeFontPreference = codeFontPreference
        self.perFileState = perFileState
        self.bookmarkStore = bookmarkStore
        self.fileReader = fileReader
        self.makeStore = makeStore
        self.makeContentView = makeContentView
        self.recentRepositoriesStore = recentRepositoriesStore
        self.repositoryIdentityResolver = repositoryIdentityResolver
        self.onRepositoryRecorded = onRepositoryRecorded
    }

    /// 差分の取得元を 1 つ作る。機能ゲートが無効なら nil で、git diff を一切実行しない。
    /// 生成をここへ限ることで、ウィンドウ側が自前で作る経路を無くしている。
    static func makeDiffLoader() -> GitDiffLoader? {
        FeatureGate.isSourceDiffEnabled ? GitDiffLoader() : nil
    }

    /// 不可視ファイル表示のON/OFFを反転し、開いている全ウィンドウのサイドバーへ即座に反映する。
    func toggleHiddenFiles() {
        sidebarDisplayPreference.showHiddenFiles.toggle()
        refreshAllSidebars()
    }

    /// git 変更ファイルのみ表示のON/OFFを反転し、開いている全ウィンドウへ即座に反映する。
    /// git 状態は取り直すが、一覧の再列挙は行わない。
    func toggleChangedFilesOnly() {
        sidebarDisplayPreference.showChangedFilesOnly.toggle()
        allControllers.forEach { $0.sidebar.applyChangedFilesOnlyToggle() }
    }

    /// サイドバーの表示モード(ドリルダウン / ツリー展開)を反転し、開いている全ウィンドウへ
    /// 即座に反映する。表示モードは行配列そのものを変えるため、各ウィンドウで行を組み直す
    /// 必要がある。ツリーからドリルダウンへ戻すときは展開状態も捨てる
    /// (捨てないと、モードを戻したのに展開したままの行が残る)。
    func toggleSidebarLayoutMode() {
        let next: SidebarLayoutMode =
            sidebarDisplayPreference.layoutMode == .tree ? .drillDown : .tree
        sidebarDisplayPreference.layoutMode = next
        if next == .drillDown {
            allControllers.forEach { $0.sidebar.discardExpansion() }
        }
        // 行の組み直しは refreshFileList の経路へ合流させる。rebuildRows を直接叩くと
        // 「ルートの一覧が届く前に行を組み直さない」不変条件を迂回することになる。
        refreshAllSidebars()
    }

    /// CLI の `--hidden-files`/`--no-hidden-files` から呼ばれる。値を直接設定し、
    /// 開いている全ウィンドウのサイドバーへ即座に反映する。
    func setHiddenFiles(_ value: Bool) {
        guard sidebarDisplayPreference.showHiddenFiles != value else { return }
        sidebarDisplayPreference.showHiddenFiles = value
        refreshAllSidebars()
    }

    /// 開いている全ウィンドウのサイドバー(ファイル一覧)を再読み込みする。
    private func refreshAllSidebars() {
        for controller in allControllers {
            controller.sidebar.refreshFileList()
        }
    }

    /// CLI の `--bookmark <path>` から転送された追加を適用し、開いている全ウィンドウの
    /// ツールバーへ即座に反映する。書き込みを GUI プロセスへ一本化する意図で
    /// AppDelegate から呼ばれる(CLIRequestForwarder 参照)。
    /// ブックマーク状態はツールバーが表示のたびに store から読み直すため、
    /// 反映は全ウィンドウの再同期で足り、変更通知の購読機構は要らない。
    func addBookmarks(for urls: [URL]) {
        for url in urls {
            bookmarkStore.add(url)
        }
        refreshAllToolbars()
    }

    /// 開いている全ウィンドウのツールバーを現在状態へ再同期する。
    private func refreshAllToolbars() {
        for controller in allControllers {
            controller.refreshToolbarState()
        }
    }

    /// codeFontPreference の現在値を、開いている全ウィンドウの WebView へ即座に反映する。
    /// フォント設定変更(環境設定 UI 等)から呼ばれる。
    func applyCodeFontToAllWindows() {
        for controller in allControllers {
            controller.applyCodeFontFromPreference()
        }
    }

    /// 既に開いているウィンドウを対象に開き直したとき(`befold --source foo.md` で foo.md が
    /// 既に開いている等)の処理。表示オプションをそのウィンドウへ適用してから前面化する。
    ///
    /// ここを素通りさせると、フラグは黙って捨てられる(TASK-413)。新規ウィンドウは
    /// ViewerWindowController.init の override 引数で同じ結果になるため、CLI オプションが
    /// 効く経路は openViewer の 1 つに揃う。
    /// 同一ファイルが複数ウィンドウで開いている場合、適用先は前面化するウィンドウ 1 つに揃える
    /// (表示モードは窓ごとのライブ値であり、窓間で同期しない = ADR 0002)。
    private func reopenExistingWindow(
        _ controller: ViewerWindowController, options: CLIOpenOptions, forceSidebarVisible: Bool
    ) {
        if let showLineNumbers = options.showLineNumbers {
            controller.store.applyShowLineNumbersOverride(showLineNumbers)
        }
        if let sourceMode = options.sourceMode { controller.applyCLIDisplayMode(isSourceMode: sourceMode) }
        // 並び順は「指定があったときだけ」触る。viewerSortOrder は未指定でも既定値を
        // 返すため、指定の有無は sortOrder の nil 判定で見る。
        if options.sortOrder != nil {
            controller.fileListModel.sortOrder = options.viewerSortOrder
            controller.sidebar.refreshFileList()
        }
        // 開閉の解決順は新規ウィンドウ(openViewer)と同じ: CLI の明示指定 > フォルダーオープンの強制表示。
        if let showSidebar = options.showSidebar {
            controller.setSidebarCollapsed(!showSidebar)
        } else if forceSidebarVisible {
            controller.setSidebarCollapsed(false)
        }
        // store の直接書き換え(行番号の上書き)はツールバーへ通知されないため、
        // 他経路の間接発火に頼らずここで明示的に再同期する。
        controller.refreshToolbarState()
        NSApp.activate()
        controller.focusWindow()
    }

    /// 指定 URL のファイルをビューアウィンドウで開く。
    /// 同じファイルが既に開かれている場合は既存ウィンドウを前面に表示する。
    ///
    /// CLI 由来の表示オーバーライドは `options` ごとそのまま受け取る。呼び出し側で
    /// フィールドを手写しして渡すと、`CLIOpenOptions` にオプションを足したときに
    /// 特定経路(セッション復元など)だけ転送漏れする。
    ///
    /// 戻り値は、この呼び出しが対象としたコントローラ(新規生成、または前面化した既存)。
    /// 開けなかった場合は nil。`controllers` は 1 パスに複数のコントローラを持ちうる
    /// 多重マップなので、呼び出し直後に `window(forPath:)` で引き直すと**別のウィンドウ**を
    /// 掴む(TASK-415)。開いたウィンドウに続けて触る呼び出し元はこの戻り値を使うこと。
    @discardableResult
    func openViewer(
        for url: URL,
        options: CLIOpenOptions = CLIOpenOptions(),
        disposition: OpenDisposition = .currentTab,
        relativeTo sourceWindow: NSWindow? = nil,
        forceSidebarVisible: Bool = false
    ) -> ViewerWindowController? {
        guard fileReader.fileExists(at: url) else {
            // 新規オープン時点ではまだ親ウィンドウが無いため over: nil でモーダル表示する。
            FileNotFoundUI.present(url: url, over: nil)
            return nil
        }

        let key = url.normalizedPathKey
        // Finder/CLI/リンクからの再オープン(.currentTab)は重複ウィンドウを作らず既存を前面化する。
        // (ウィンドウ内のサイドバー切替だけは他ウィンドウを無視して自ウィンドウを切り替える)
        // 一方 .newTab/.newWindow は cmd+クリックやコンテキストメニューでユーザーが
        // 明示的に新規オープンを求めた経路なので、重複抑止より意図を優先して素通しする
        // (既に開いているファイルで「新しいウィンドウで開く」が無反応に見える問題: issue #431)。
        if disposition == .currentTab, let existing = controllers[key]?.first {
            reopenExistingWindow(existing, options: options, forceSidebarVisible: forceSidebarVisible)
            return existing
        }

        let lastActivePathKey = sessionStore.savedActivePath()
        // 開閉の解決順: CLI の明示指定(--sidebar/--no-sidebar) > フォルダーオープンによる強制表示 > 記憶の引き継ぎ。
        let initialSidebarCollapsed: Bool = if let showSidebar = options.showSidebar {
            !showSidebar
        } else if forceSidebarVisible {
            false
        } else {
            perFileState.sidebar.initialCollapsed(for: url, lastActivePathKey: lastActivePathKey)
        }
        perFileState.sidebar.setCollapsed(initialSidebarCollapsed, for: url)

        let initialFrameDescriptor = perFileState.windowFrame.initialFrameDescriptor(
            for: url, lastActivePathKey: lastActivePathKey
        )
        if let initialFrameDescriptor {
            perFileState.windowFrame.setFrameDescriptor(initialFrameDescriptor, for: url)
        }

        let controller = ViewerWindowController(
            fileURL: url,
            sidebarDisplayPreference: sidebarDisplayPreference,
            diffDisplayPreference: diffDisplayPreference,
            diffLoader: diffLoader,
            findOptionsPreference: findOptionsPreference,
            codeFontPreference: codeFontPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            gitFileIndex: gitFileIndex,
            gitStatusStore: gitStatusStore,
            initialSidebarCollapsed: initialSidebarCollapsed,
            initialFrameDescriptor: initialFrameDescriptor,
            initialSortOrder: options.viewerSortOrder,
            showLineNumbersOverride: options.showLineNumbers,
            sourceModeOverride: options.sourceMode,
            store: makeStore?(url),
            makeContentView: makeContentView,
            openFileElsewhere: { [weak self] fileURL, disposition, sourceWindow in
                self?.openViewer(for: fileURL, disposition: disposition, relativeTo: sourceWindow)
            }
        )
        controllers[key, default: []].append(controller)
        controller.delegate = self
        NSApp.activate()
        controller.showWindow(nil)
        // window が nil(生成直後で取得できない等)ならタブ結合をあきらめ独立ウィンドウのまま
        // 表示する(attachAsTab と同じ「開けないよりタブにならない」への縮退)。
        if disposition == .newTab, let window = controller.window {
            attachAsTab(window, to: sourceWindow, select: true)
        }
        sessionStore.noteOpened(url)
        recentDocumentsStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recordRecentRepositoryIfNeeded(for: url, controller: controller)
        return controller
    }

    /// window を baseWindow のタブグループへ結合する。タブ結合の手続きはここが単一の実装元で、
    /// セッション復元(SessionRestorer.restoreTabGroup)も同じ経路を通る。
    /// baseWindow が nil のときは何もしない = 独立したウィンドウのままにする
    /// (「開けない」より「タブにならない」へ縮退させる)。
    /// - Parameter select: 結合したタブを選択状態にするか。復元時は元の選択タブを別途決めるため false。
    func attachAsTab(_ window: NSWindow, to baseWindow: NSWindow?, select: Bool) {
        guard let baseWindow, baseWindow !== window else { return }
        baseWindow.addTabbedWindow(window, ordered: .above)
        if select {
            window.tabGroup?.selectedWindow = window
        }
    }

    /// ウィンドウが「表示中のはずなのにアクティブ Space に居ない」状態かを判定する。
    static func isDetachedFromSpace(isVisible: Bool, isOnActiveSpace: Bool) -> Bool {
        isVisible && !isOnActiveSpace
    }

    /// Space に載れなかった可視ウィンドウを現在の Space に載せ直す。
    /// アップデータによる再起動では、旧プロセス終了直後の WindowServer 遷移状態で
    /// 復元ウィンドウがどの Space にも属さず不可視になることがある(再 orderFront で復旧する)。
    /// 起動直後にのみ呼ぶこと(ユーザーが他 Space に移した後のウィンドウに触れないように)。
    func rescueWindowsDetachedFromSpace() {
        for controller in allControllers {
            guard let window = controller.window,
                  Self.isDetachedFromSpace(
                      isVisible: window.isVisible, isOnActiveSpace: window.isOnActiveSpace
                  )
            else { continue }
            window.orderFront(nil)
        }
    }

    /// url が git リポジトリ内なら「最近使ったリポジトリ」に記録し、ウィンドウへ
    /// ルートをキャッシュする(ウィンドウを閉じる際に再度 git を呼ばずに済ませるため)。
    ///
    /// ルート解決とラベル解決はどちらも git の subprocess を待ち、しかも
    /// GitCommandFileIndex の共有ロックの内側で直列化される。MainActor で同期実行すると
    /// ウィンドウを開くたびに UI が止まるため、解決は detached タスクで行い、結果の反映だけ
    /// MainActor へ戻す(SidebarNavigator の resolveGitRoot と同じ方針)。
    /// 解決が終わる前にウィンドウが閉じられた場合、そのウィンドウ分の記録は行われない
    /// (履歴が1件増えないだけで、次に開いたときに記録されるため許容する)。
    private func recordRecentRepositoryIfNeeded(for url: URL, controller: ViewerWindowController) {
        let gitFileIndex = gitFileIndex
        let resolveIdentity = repositoryIdentityResolver
        Task.detached { [weak self, weak controller] in
            guard let root = gitFileIndex.repositoryRoot(forFileAt: url) else { return }
            let identity = resolveIdentity(root)
            await self?.applyRecentRepository(root: root, identity: identity, to: controller)
        }
    }

    /// detached タスクで解決した git ルート/identity を MainActor 上で反映する。
    /// ウィンドウが既に閉じられていれば(controller == nil)何もしない。
    /// mainRoot は worktree のときだけ渡す(本体そのものなら nil。RecentRepositoryEntry の規約)。
    private func applyRecentRepository(
        root: URL, identity: RepositoryIdentity, to controller: ViewerWindowController?
    ) {
        guard let controller else { return }
        controller.repositoryRoot = root
        let isMainRepository = identity.mainRoot.normalizedPathKey == root.normalizedPathKey
        recentRepositoriesStore.record(
            root: root, label: identity.label, mainRoot: isMainRepository ? nil : identity.mainRoot
        )
        onRepositoryRecorded(identity.mainRoot)
    }

    /// controller のウィンドウ(自身のタブグループ)の構成を「最近使ったリポジトリ」へ記録する。
    ///
    /// タブ構成を正しく観測できるのはウィンドウが生きている間だけである。
    /// windowWillClose の時点では AppKit が既にそのウィンドウをタブグループから外していて
    /// (`window.tabGroup == nil`)、閉じる1枚分しか組み立てられない。そのため
    /// アクティブ化のたびに現在の構成を記録し、close 時に届く縮小した構成は
    /// updateLastTabGroup の部分集合拒否で捨てる。
    private func recordRecentRepositoryTabGroup(
        of controller: ViewerWindowController, force: Bool = false
    ) {
        guard let root = controller.repositoryRoot, let window = controller.window,
              let group = tabGroup(of: window)
        else { return }
        recentRepositoriesStore.updateLastTabGroup(root: root, group, force: force)
    }

    /// 開いている全ウィンドウの現在のタブ構成を「最近使ったリポジトリ」へ記録する。
    /// アプリ終了時に呼ぶ。終了では windowWillClose が発火しないことがあり、
    /// close 経路だけではタブ構成を取りこぼす。終了時点の構成を正として force 付きで
    /// 上書きする(ユーザーが意図的にタブを減らした結果は、セッション中の
    /// 縮小拒否を通り抜けられるこの経路でしか反映できない)。
    func recordAllRecentRepositoryTabGroups() {
        for controller in allControllers {
            recordRecentRepositoryTabGroup(of: controller, force: true)
        }
    }

    /// window が属するタブグループのウィンドウ群。タブ化されていなければ自身のみ。
    /// タブ構成のスナップショットを取る側(セッション保存・最近使ったリポジトリ)が
    /// 同じ解釈を共有するための単一の入口。
    static func tabWindows(of window: NSWindow) -> [NSWindow] {
        window.tabGroup?.windows ?? [window]
    }

    /// タブ構成スナップショットの組み立て本体(NSWindow に依存しない純粋関数)。
    /// 「終了時レイアウト」と「最近使ったリポジトリのタブ構成」は同じ形式で相互に
    /// 保存・復元されるため、組み立て規則はここ 1 箇所だけに置く。
    /// ビューアパスを 1 つも持たなければ nil(ビューアウィンドウでない・全タブが閉じた等)。
    static func makeTabGroup<Window>(
        tabWindows: [Window], selectedWindow: Window, viewerPath: (Window) -> String?
    ) -> SessionLayout.TabGroup? {
        let paths = tabWindows.compactMap(viewerPath)
        guard !paths.isEmpty else { return nil }
        return SessionLayout.TabGroup(paths: paths, selectedPath: viewerPath(selectedWindow))
    }

    /// window(自身のタブグループ)を SessionLayout.TabGroup として組み立てる。
    /// タブが1枚も無ければ nil(ビューアウィンドウでない・既に全タブが閉じた等)。
    func tabGroup(of window: NSWindow) -> SessionLayout.TabGroup? {
        Self.makeTabGroup(
            tabWindows: Self.tabWindows(of: window),
            selectedWindow: window.tabGroup?.selectedWindow ?? window,
            viewerPath: viewerPath(of:)
        )
    }

    /// 指定の正規化パスに対応する開状態のウィンドウを返す。
    /// 同一ファイルを複数ウィンドウで開いている場合は、そのいずれか(先頭)を返す。
    func window(forPath path: String) -> NSWindow? {
        controllers[path]?.first?.window
    }

    /// controller を key のコントローラ群から取り除き、空になったキーは辞書から消す。
    private func detach(_ controller: ViewerWindowController, fromKey key: String) {
        guard var list = controllers[key] else { return }
        list.removeAll { $0 === controller }
        controllers[key] = list.isEmpty ? nil : list
    }

    /// url を表示しているウィンドウが 1 つも残っていなければ、セッション記録から閉じたことにする。
    ///
    /// 同一ファイルを複数ウィンドウで開くことを許している(controllers は 1 対多)ため、
    /// 閉じる/切り替えるたびに無条件で noteClosed を呼ぶと、まだ表示している窓が残っていても
    /// セッション集合とアクティブ記録から消える(TASK-412)。参照が残っているかの判定は
    /// controllers の有無そのもので足りるので、SessionStore 側に参照カウントは持たせない。
    /// close 経路と remap 経路が別々の判定を持たないよう、必ずここを通す。
    private func noteClosedIfNoWindowRemains(for url: URL) {
        guard controllers[url.normalizedPathKey] == nil else { return }
        sessionStore.noteClosed(url)
    }

    /// ビューアウィンドウなら対応するファイルの正規化パスを返す。
    func viewerPath(of window: NSWindow) -> String? {
        (window.windowController as? ViewerWindowController)?.fileURL.normalizedPathKey
    }

    /// rename / switch に伴うウィンドウ管理辞書のキー付け替えとセッション・履歴の更新。
    private func remapController(
        _ controller: ViewerWindowController,
        from oldURL: URL,
        to newURL: URL,
        isRename: Bool
    ) {
        let oldKey = oldURL.normalizedPathKey
        let newKey = newURL.normalizedPathKey
        detach(controller, fromKey: oldKey)
        controllers[newKey, default: []].append(controller)
        if isRename {
            sessionStore.noteRenamed(from: oldURL, to: newURL)
        }
        noteClosedIfNoWindowRemains(for: oldURL)
        sessionStore.noteOpened(newURL)
        if isRename {
            recentDocumentsStore.noteRenamed(from: oldURL, to: newURL)
            bookmarkStore.noteRenamed(from: oldURL, to: newURL)
        } else {
            recentDocumentsStore.noteOpened(newURL)
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
    }
}

// MARK: - ViewerWindowControllerDelegate

extension ViewerWindowManager: ViewerWindowControllerDelegate {
    func viewerWindowWillClose(_ controller: ViewerWindowController) {
        recordRecentRepositoryTabGroup(of: controller)
        detach(controller, fromKey: controller.fileURL.normalizedPathKey)
        noteClosedIfNoWindowRemains(for: controller.fileURL)
    }

    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController) {
        sessionStore.noteActivated(controller.fileURL)
        // タブグループが壊れていない状態を観測できる唯一の契機。ここで記録しておかないと、
        // タブを複数開いたウィンドウの構成は close 時には既に失われている。
        recordRecentRepositoryTabGroup(of: controller)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL
    ) {
        remapController(controller, from: oldURL, to: newURL, isRename: true)
    }

    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    ) {
        remapController(controller, from: oldURL, to: newURL, isRename: false)
    }

    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController) {
        toggleHiddenFiles()
    }

    func viewerWindowDidToggleChangedFilesOnly(_ controller: ViewerWindowController) {
        toggleChangedFilesOnly()
    }

    func viewerWindowDidToggleDiffLayout(_ controller: ViewerWindowController) {
        refreshAllToolbars()
    }
}
