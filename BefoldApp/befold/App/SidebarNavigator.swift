import BefoldKit
import Foundation

/// SidebarNavigator がファイル切替・現在ファイル参照を委譲する先。
/// ViewerWindowController が実装する。循環参照を避けるため SidebarNavigator からは weak 参照する。
@MainActor
protocol SidebarNavigatorHost: AnyObject {
    /// 現在表示中のファイル URL。performFileSwitch により変化するため都度参照する。
    var currentFileURL: URL { get }
    /// サイドバー選択・履歴から要求されたファイル切替の実処理。
    /// 別ウィンドウで開いている・存在しないなど切替できなかった理由は結果で返る。
    @discardableResult
    func performFileSwitch(to url: URL) -> FileSwitchOutcome
    /// 戻る/進む履歴の状態が変化した。AppKit 側 UI(ツールバー)の更新契機。
    func historyStateDidChange()
    /// git 状態(サイドバーのバッジ)が反映された。表示中ファイルの差分など、
    /// バッジと同じ契機で取り直すべきものの更新点。
    ///
    /// 「バッジと差分の更新契機を 1 つにする」判断を、コンパイル時に守らせるための必須メソッド。
    /// 呼び分けを増やすと、契機がまた片方だけに増える(TASK-330)。
    func gitStatusDidApply()
}

/// サイドバー(ファイル一覧・選択同期・フォルダ移動)と戻る/進む履歴を管理する。
/// ファイル切替そのものは host(ViewerWindowController)へ委譲し、本クラスは
/// 一覧の再取得・選択同期・履歴の記録/適用に責務を絞る。
@MainActor
final class SidebarNavigator {
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    let fileListModel: FileListModel
    /// 戻る/進む履歴の記録と適用。`tree` などと同じく注入引数にせず内部で生成する。
    private let historyController: SidebarHistoryController
    /// ディレクトリごとの「そこを離れる直前に選択していた項目」(正規化キー → URL)。
    /// 再びそのフォルダーへ入ったときの選択復元だけに使う(TASK-309)。メモリ内のみで、
    /// ウィンドウの生存期間で自然に消える。
    ///
    /// **触れるのは直下の 2 つのヘルパーだけ**で、それを `private` で強制している
    /// (以前は別ファイルの extension に置いていたため internal にせざるを得なかった)。
    private var selectionMemory: [String: URL] = [:]

    /// 現在の選択を、そのディレクトリを離れる直前の選択として覚える。
    /// 選択が無いときは記憶を消し、次回の再訪で既定の挙動へ戻す。
    /// 呼ぶのは navigateToFolder だけ(SidebarNavigator+FolderNavigation.swift)。
    func rememberSelection(in directory: URL) {
        selectionMemory[directory.normalizedPathKey] = fileListModel.selection
    }

    /// `directory` で覚えている選択のうち、いま見えている一覧に残っているものを返す。
    /// 削除・リネーム・絞り込みで見えない場合は nil を返し、既定挙動へ委ねる。
    func rememberedSelectionURL(in directory: URL) -> URL? {
        guard let remembered = selectionMemory[directory.normalizedPathKey] else { return nil }
        let key = remembered.normalizedPathKey
        return fileListModel.visibleEntries.first { $0.kind != .parentNavigation && $0.pathKey == key }?.url
    }

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
        sidebarDisplayPreference: SidebarDisplayPreference,
        sortOrder: SortOrder = .foldersFirst,
        directoryLister: @escaping (URL, SortOrder, Bool) async -> DirectoryListing
            = DirectoryLister.listingAsync,
        childrenLister: @escaping (URL, SortOrder, Bool) async -> [FileListEntry]?
            = DirectoryLister.childEntriesAsync,
        git: any SidebarGitReading = DisabledSidebarGitReading(),
        makeGitIndexWatcher: @escaping GitIndexWatch.WatcherFactory
            = { url, onChange in FileWatcher(path: url, onChange: onChange) }
    ) {
        let fileListModel = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection,
            sortOrder: sortOrder
        )
        self.fileListModel = fileListModel
        // 協力型は**ここでしか生成しない**(注入引数にすると渡し忘れが静かに
        // 別インスタンスになる / TASK-319 と同型)。クロージャは素通しする。
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
            sidebarDisplayPreference: sidebarDisplayPreference,
            tree: tree,
            gitStatus: gitStatus,
            baseDirectory: baseDirectory
        )
        listing.syncDisplayPreferences()
        baseDirectory.refresh()
    }

    // MARK: - File List

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

    /// fileListModel 側の表示設定ミラーを真実の源へ同期する。実処理は
    /// SidebarListingCoordinator が持つ(表示設定は列挙の入力なので)。
    /// 「変更ファイルのみ表示」のトグルは applyChangedFilesOnlyToggle() を使うこと。
    @discardableResult
    func syncDisplayPreferences() -> Bool {
        listing.syncDisplayPreferences()
    }

    /// 「変更ファイルのみ表示」トグル時に呼ぶ。表示述語を同期し、ON になったときだけ
    /// git 状態を取り直す(再列挙はしない)。
    /// ON で取り直すのは、作業ツリーの編集が index も windowDidBecomeKey も動かさず、
    /// 古い状態で絞り込まれてしまうため(TASK-296)。
    /// OFF は絞り込みをやめるだけで新しい git 状態を必要とせず、バッジは手元のスナップショットで
    /// 足りる。方向を見ずに取り直すと、開いているウィンドウ数だけ git status が同時に走る(TASK-303)。
    func applyChangedFilesOnlyToggle() {
        syncDisplayPreferences()
        guard fileListModel.showChangedFilesOnly else { return }
        refreshGitStatuses()
    }

    /// host を接続する。ViewerWindowController が super.init 後に呼ぶ。
    /// git 状態・履歴の通知先も同じ host なので、ここで一緒に結線する。
    func attach(to host: SidebarNavigatorHost) {
        self.host = host
        listing.attach(to: host)
        gitStatus.attach(to: host)
        historyController.attach(to: host, navigator: self)
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

    /// 展開状態を捨てる。ツリー表示をやめるとき(ViewerWindowManager)に呼ぶ。
    /// 行の組み直しは呼び出し側が refreshFileList の経路で行うこと。
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
    func syncAfterSwitch(to newURL: URL) {
        let newDir = newURL.deletingLastPathComponent().normalizedPathKey
        if newDir != fileListModel.currentDirectory.normalizedPathKey {
            fileListModel.currentDirectory = newURL.deletingLastPathComponent()
            refreshFileList()
        } else {
            fileListModel.selection = fileListModel.matchingEntryURL(for: newURL)
        }
        recordHistory()
    }

    /// ファイル切替が別ウィンドウ移譲・失敗で成立しなかったときに選択を元へ戻す。
    func restoreSelection(to url: URL) {
        fileListModel.selection = url
    }
}
