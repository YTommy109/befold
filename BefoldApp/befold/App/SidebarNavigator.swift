import BefoldKit
import Foundation

/// サイドバー(ファイル一覧・選択同期・フォルダ移動)と戻る/進む履歴を管理する。
/// ファイル切替そのものは host(ViewerWindowController)へ委譲し、本クラスは
/// 一覧の再取得・選択同期・履歴の記録/適用に責務を絞る。
@MainActor
final class SidebarNavigator {
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    let fileListModel: FileListModel
    /// 戻る/進む履歴の記録と適用。`tree` などと同じく注入引数にせず内部で生成する。
    private let historyController: SidebarHistoryController

    /// このタブの戻る/進む履歴(読み取り専用)。ツールバー・メニュー判定はここを見る。
    /// 書き換えるのは `historyController` だけなので、写しを持つ必要がない(TASK-458)。
    var navigationHistory: NavigationHistory {
        historyController.history
    }

    /// ディレクトリごとの「そこを離れる直前に選択していた項目」の記憶(TASK-309)。
    /// 触るのはフォルダー移動(SidebarNavigator+FolderNavigation.swift)だけなので
    /// `private` にはできない(Swift の `private` はファイルスコープ)。
    let selectionMemory: SidebarSelectionMemory

    /// サイドバーの行の組み立てと `fileListModel.entries` への反映(ツリー展開を含む)。
    ///
    /// **注入引数にしない。** デフォルト引数で外から渡せる形にすると、渡し忘れが
    /// コンパイルエラーにならず静かに別インスタンスになる(TASK-319 と同型)。
    /// ウィンドウごとに 1 つという粒度を、生成箇所をここ 1 つに固定することで守る。
    ///
    /// **`private`。** 外へ出すと `applyRows` / `invalidateExpansion` までウィンドウ層から
    /// 到達可能になり、「外から呼んでよいのは展開・畳みだけ」が doc の約束に戻る
    /// (以前 ViewerWindowManager が `expansion.invalidateAll()` を直接叩いて実際に破れていた)。
    /// 外部へは下の薄い委譲(expandFolder / collapseFolder / discardExpansion /
    /// applyRows)だけを見せる。
    private let tree: SidebarTreePresenter
    /// 一覧取得の発行と世代管理、および表示設定ミラーの同期(列挙の入力なので同居)。
    private let listing: SidebarListingCoordinator
    /// ツリー⇄リスト切り替えの遷移方針(スナップショットの記録・復元と経路の展開)。
    private let layoutTransition: SidebarLayoutTransition
    /// 相対パスコピー・Quick Open のヘッダーが使う基準ディレクトリの解決。
    /// **`tree` と同じく注入引数にせず private で持つ**(TASK-319 / 442.3 と同型)。
    private let baseDirectory: SidebarBaseDirectoryResolver
    /// git 状態(バッジ・絞り込みの材料)の取得と反映。
    /// 発行順序の採番はこの型の内側に閉じており、本クラスは sequence を読み書きしない。
    private let gitStatus: SidebarGitStatusCoordinator

    /// ファイル切替・現在ファイル参照の委譲先。循環参照を避けるため weak。
    ///
    /// **`private` へは戻せない**(TASK-442.5 / AC#5)。Swift の `private` は
    /// ファイルスコープで、別ファイルの extension である
    /// SidebarNavigator+FolderNavigation.swift が `host != nil` の確認と
    /// `select(_:presentingWith:)` への受け渡しで読むため。e94161d で
    /// `private` → `private(set)` へ緩んだのは読み取り側だけで、**書き込みを
    /// `attach(to:)` に限定する**当初の意図は `private(set)` で保たれている。
    private(set) weak var host: SidebarNavigatorHost?

    // MARK: - Initialization

    init(
        currentDirectory: URL, entries: [FileListEntry], selection: URL?,
        displayDefaults: any SidebarDisplayDefaultsProviding,
        sortOrder: SortOrder? = nil,
        showHiddenFiles: Bool? = nil,
        directoryLister: @escaping (URL, SortOrder, Bool) async -> DirectoryListing
            = DirectoryLister.listingAsync,
        childrenLister: @escaping (URL, SortOrder, Bool) async -> [FileListEntry]?
            = DirectoryLister.childEntriesAsync,
        git: any SidebarGitReading = DisabledSidebarGitReading(),
        makeGitIndexWatcher: @escaping GitIndexWatch.WatcherFactory
            = { url, onChange in FileWatcher(path: url, onChange: onChange) }
    ) {
        // 窓ごとのライブ値の初期値。CLI の明示指定(--sort / --hidden-files)があればそれで上書きし、
        // 無ければ前回保存した既定値から始める。**既定値を読むのはここ 1 回だけ。**
        // displayDefaults は保持しないため以後読み直せず、窓の内側(listing)へ渡すのは
        // 書き戻し専用の SidebarDisplayDefaultsRecording としてのみ(ADR 0002「窓の状態の規則」2)。
        var initialSettings = displayDefaults.settings
        if let sortOrder {
            initialSettings.sortOrder = sortOrder
        }
        if let showHiddenFiles {
            initialSettings.showHiddenFiles = showHiddenFiles
        }
        let fileListModel = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection,
            display: initialSettings
        )
        self.fileListModel = fileListModel
        // 協力型は**ここでしか生成しない**(注入引数にすると渡し忘れが静かに
        // 別インスタンスになる / TASK-319 と同型)。クロージャは素通しする。
        selectionMemory = SidebarSelectionMemory(fileListModel: fileListModel)
        tree = SidebarTreePresenter(fileListModel: fileListModel, childrenLister: childrenLister)
        baseDirectory = SidebarBaseDirectoryResolver(
            fileListModel: fileListModel, git: git
        )
        gitStatus = SidebarGitStatusCoordinator(
            fileListModel: fileListModel,
            git: git,
            makeGitIndexWatcher: makeGitIndexWatcher
        )
        historyController = SidebarHistoryController(fileListModel: fileListModel)
        listing = SidebarListingCoordinator(
            fileListModel: fileListModel,
            directoryLister: directoryLister,
            displayDefaults: displayDefaults,
            tree: tree,
            gitStatus: gitStatus,
            baseDirectory: baseDirectory
        )
        layoutTransition = SidebarLayoutTransition(fileListModel: fileListModel, tree: tree, listing: listing)
        baseDirectory.refresh()
    }

    // MARK: - File List

    /// サイドバー表示 4 値を変える唯一の入口。実処理は SidebarListingCoordinator が持つ
    /// (4 値は列挙の入力なので)。**メニュー・サイドバーヘッダー・CLI はすべてここを通す。**
    func applyDisplayChange(_ change: SidebarDisplayChange) {
        // レイアウトだけは前後にカレントの移動・展開の温存/復元が付く(TASK-481)。
        if case .toggleLayoutMode = change {
            layoutTransition.toggleLayoutMode()
        } else {
            listing.applyDisplayChange(change)
        }
    }

    /// サイドバーのファイル一覧を取り直す。実処理は SidebarListingCoordinator が持つ。
    func refreshFileList(applyCustomSelection: (() -> Bool)? = nil) {
        listing.refreshFileList(applyCustomSelection: applyCustomSelection)
    }

    /// 世代ガード付きの一覧取得。SidebarNavigator+FolderNavigation からも呼ぶため internal。
    func performListing(
        of directory: URL,
        onApplied: @escaping @MainActor (SidebarNavigatorHost, URL, DirectoryListing) -> Void
    ) {
        listing.performListing(of: directory, onApplied: onApplied)
    }

    /// 発行済みのサイドバー更新(一覧・git 状態・基準ディレクトリ)が反映され終わるまで待つ。
    /// **テストが待ち合わせに使う既定の入口はここ**で、個別の `pending*Task` ではない。
    ///
    /// 1 回の `performListing` は 3 本のタスクを発行し、そのうちどれが git 状態の反映を
    /// 運ぶかは絞り込み(showChangedFilesOnly)の ON/OFF で変わる(ON なら一覧タスクの中、
    /// OFF なら git タスク / TASK-293)。3 本すべてを待てばその分岐を呼び出し側が知る必要が
    /// なくなるため、「どれを待つか」を選ばせない形にしている。未発行・完了済みの窓は
    /// nil か即時完了で、待っても無害。
    ///
    /// **待てるのは「呼んだ時点で発行済み」の仕事だけ**。取り直しがまだ発行されていない
    /// 段階で呼ぶと、その取り直しの前に測ってしまう(前回の完了済みタスクを観測して即座に
    /// 戻る)。再取得が起きたこと自体を観測したいテストは、ハンドルを先に掴むか
    /// `waitUntil` 系で結果側を待つこと(実例: ViewerWindowControllerGitStatusTests)。
    func awaitSettled() async {
        await pendingListingTask?.value
        await pendingGitStatusTask?.value
        await pendingBaseDirectoryTask?.value
    }

    /// 直近に発行した一覧取得タスク。**ハンドルを先に掴んでおく競合テスト専用の窓**
    /// (通常の待ち合わせは `awaitSettled()` を使う。理由はそちらの doc を参照)。
    var pendingListingTask: Task<Void, Never>? {
        listing.pendingTask
    }

    // MARK: - Git Status

    /// 表示中ディレクトリの git 状態を取り直して fileListModel へ反映する。
    /// 実処理は SidebarGitStatusCoordinator が持つ。
    /// - Parameter policy: `.onlyIfIndexChanged` は `.git/index` が動いていないとき git を起こさない
    ///   (`.git` 配下の書き込み通知が契機のとき用)。それ以外の契機では `.always` を使うこと。
    func refreshGitStatuses(policy: GitStatusRefreshPolicy = .always) {
        gitStatus.refresh(policy: policy)
    }

    /// 直近に発行した git 状態取得タスク。**ハンドルを先に掴んでおく競合テスト専用の窓**
    /// (通常の待ち合わせは `awaitSettled()` を使う)。
    ///
    /// ここに載るのは常に単発の git 取得だけで、絞り込み ON のときの反映は一覧タスクの
    /// 中で起きる(TASK-293)。`awaitSettled()` はこの分岐を吸収するが、この窓を直接
    /// 使う場合は分岐が見えたままになる。
    var pendingGitStatusTask: Task<Void, Never>? {
        gitStatus.pendingTask
    }

    /// 直近に発行した基準ディレクトリ解決タスク。**ハンドルを先に掴んでおく競合テスト専用の窓**
    /// (通常の待ち合わせは `awaitSettled()` を使う)。
    var pendingBaseDirectoryTask: Task<Void, Never>? {
        baseDirectory.pendingTask
    }

    /// host を接続する。ViewerWindowController が super.init 後に呼ぶ。
    /// git 状態・履歴の通知先も同じ host なので、ここで一緒に結線する。
    /// - Parameter adopting: 起点の窓が列挙済みの一覧。引き継げる組み合わせなら出発点に
    ///   する(判定は `SidebarListingSeed.canApply(to:)` / TASK-532)。nil もここで受ける
    ///   ——呼び出し側へ分岐を置くと窓の生成手順が 2 本に割れる。**取り付けと同じ区間で
    ///   当てる**ので、最初の `refreshFileList` より前になることが構造で決まる。
    func attach(to host: SidebarNavigatorHost, adopting seed: SidebarListingSeed? = nil) {
        self.host = host
        listing.attach(to: host)
        gitStatus.attach(to: host)
        baseDirectory.attach(to: host)
        historyController.attach(to: host, navigator: self)
        layoutTransition.attach(to: self)
        guard let seed, seed.canApply(to: fileListModel) else { return }
        applyRows(seed.listing, for: seed.directory)
    }

    // MARK: - Navigation History

    /// 戻る/進む。offset 負=戻る / 正=進む。実処理は SidebarHistoryController が持つ。
    func navigateHistory(by offset: Int) {
        historyController.navigate(by: offset)
    }

    /// 現在の表示状態(ディレクトリ＋ファイル)を履歴に記録する。
    func recordHistory() {
        historyController.record()
    }

    /// rename/move を履歴へ反映する。
    func applyRename(from oldURL: URL, to newURL: URL) {
        historyController.applyRename(from: oldURL, to: newURL)
    }

    // MARK: - Tree Expansion

    /// サイドバーのフォルダを展開する。実処理は SidebarTreePresenter が行う。
    ///
    /// 以下 3 本が、**外から展開へ触れる唯一の入口**。presenter 自体を公開すると
    /// 行の反映(applyRows)まで到達可能になるため、薄い委譲だけを見せる。
    func expandFolder(_ key: String, at url: URL) {
        tree.expandFolder(key, at: url)
    }

    /// サイドバーのフォルダを畳む。配下の展開も一緒に捨てる。
    func collapseFolder(_ key: String) {
        tree.collapseFolder(key)
    }

    /// 展開状態を捨てる。ツリー表示中のフォルダー移動(moveCurrentDirectory)から呼ぶ。レイアウト
    /// 切り替えでの破棄判断は SidebarLayoutTransition が持つ(リスト化では温存する / TASK-481)。
    func discardExpansion() {
        tree.invalidateExpansion()
    }

    /// 展開中フォルダの pathKey。テストが展開状態を検証するための読み取り専用の窓。
    var expandedFolderKeys: Set<String> {
        tree.expandedKeys
    }

    /// 列挙結果から行を組み立てて fileListModel へ反映し、反映した行を返す。
    ///
    /// **一覧取得の着地点(performListing の onApplied)だけが呼ぶ。** 呼び出し元が
    /// 2 つ(refreshFileList / navigateToFolder)に分かれているのは、前者だけが
    /// 「開いているファイルを一覧へ必ず含める」加工を挟むため。presenter そのものを
    /// 公開せずこの 1 本だけ委譲するのは、別ファイルの extension
    /// (SidebarNavigator+FolderNavigation)から呼ぶ必要があるから。
    @discardableResult
    func applyRows(_ listing: DirectoryListing, for directory: URL) -> [FileListEntry] {
        tree.applyRows(listing, for: directory)
    }

    /// 直近に反映した列挙結果(行に畳む前の材料)。新しい窓の出発点として渡すために読む
    /// (`SidebarListingSeed` / TASK-532)。組み立ては `ViewerWindowManager` の側。
    var lastListing: DirectoryListing {
        tree.lastListing
    }

    /// 進行中の取得をすべて破棄する。ウィンドウを閉じるときに呼ぶ。
    /// キャンセルは協調的で、走り出した subprocess は完了して結果を返しうる。番号を進めて
    /// おかないとその結果が反映ガードを通り抜け、閉じたウィンドウのために `.git/index`
    /// 監視を張り直す(以後リポジトリを触るたび git が起動し続ける / TASK-300)。
    func cancelPendingListing() {
        // 協力型が持つ進行中の処理は、それぞれの型の 1 メソッドへ畳んである。
        // ここに個別の世代加算や pending の nil 代入が戻ってきたら、分離が崩れている。
        listing.cancelPending()
        baseDirectory.cancelPending()
        gitStatus.cancelPending()
        // 展開の子リスト取得も無効化する。ここを忘れると、閉じたウィンドウのために
        // 走行中だった列挙が着地して状態を書き続ける(TASK-300 と同型)。
        tree.invalidateExpansion()
    }

    /// switchFile 成功後にサイドバー選択を同期し、履歴を記録する。
    /// ViewerWindowController.switchFile がファイル切替の実処理後に呼ぶ。
    ///
    /// 移動・選択の確定・取り直しの実処理は `SidebarPostSwitchSync` が持つ(履歴の適用と
    /// 同じ区間を通すため / TASK-471)。ここで決めるのは「動かすかどうか」だけ。
    /// 判定の基準はレイアウトではなく「いま一覧にその行があるか」で、一覧に既にあるなら
    /// 取り直す理由も無い(tree の展開下の子行を選んだだけで移動させない / TASK-465)。
    func syncAfterSwitch(to newURL: URL) {
        let needsMove = !fileListModel.isReachableInCurrentListing(newURL)
        SidebarPostSwitchSync.apply(
            on: self,
            movingTo: needsMove ? newURL.deletingLastPathComponent() : nil,
            selecting: newURL,
            refreshesWhenStaying: false
        )
        recordHistory()
    }

    /// ファイル切替が別ウィンドウ移譲・失敗で成立しなかったときに選択を元へ戻す。
    func restoreSelection(to url: URL) {
        fileListModel.selection = url
    }
}
