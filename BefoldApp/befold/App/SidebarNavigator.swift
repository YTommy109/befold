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
    /// このタブの戻る/進むナビゲーション履歴(メモリ内のみ)。
    let history = NavigationHistory()
    /// ディレクトリごとの「そこを離れる直前に選択していた項目」(正規化キー → URL)。
    /// 再びそのフォルダーへ入ったときの選択復元だけに使う(TASK-309)。
    /// 履歴(NavigationHistory)と同じくメモリ内のみで、ウィンドウの生存期間で自然に消える。
    /// 読み書きは SidebarNavigator+SelectionMemory.swift の 2 つのヘルパーだけが行う。
    var selectionMemory: [String: URL] = [:]
    /// 不可視ファイル表示設定。全ウィンドウで共有される単一の真実の源を都度参照する。
    private let sidebarDisplayPreference: SidebarDisplayPreference
    /// ファイル一覧の再取得元。既定は DirectoryLister.listingAsync(nonisolated async)だが、
    /// 再読込経路をテストで差し替えられるよう注入可能にする。async のため呼び出し元アクター
    /// (MainActor)を離れて実行され、巨大ディレクトリでもメインスレッドを塞がない。
    ///
    /// 返すのは **行に畳む前の材料**(DirectoryListing)。畳んだ配列を返させると、
    /// 展開を足す側がそれを分解して材料へ戻す往復が要る(TASK-442.1)。
    private let directoryLister: (URL, SortOrder, Bool) async -> DirectoryListing
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
    /// refreshFileList / navigateToFolder が発行する一覧取得タスクの世代番号。
    /// 新しい要求が来たら古い結果の反映を捨てる(ViewerStore.loadGeneration と同型)。
    private var listingGeneration = 0
    /// 直近に発行した一覧取得タスク。テストから完了を待つために公開する。
    ///
    /// 絞り込み ON のときは git 状態の反映もこのタスクの中で起きる(一覧と git を
    /// 同一メインアクター実行で反映するのが不変条件 / TASK-293)。ON の反映完了を
    /// 待ちたいテストは `gitStatus` 側ではなくこれを待つこと。
    private(set) var pendingListingTask: Task<Void, Never>?
    /// 相対パスコピー・Quick Open のヘッダーが使う基準ディレクトリの解決。
    /// **`tree` と同じく注入引数にせず private で持つ**(TASK-319 / 442.3 と同型)。
    private let baseDirectory: SidebarBaseDirectoryResolver
    /// git 状態(バッジ・絞り込みの材料)の取得と反映。
    /// 発行順序の採番はこの型の内側に閉じており、本クラスは sequence を読み書きしない。
    private let gitStatus: SidebarGitStatusCoordinator

    /// ファイル切替・現在ファイル参照の委譲先。循環参照を避けるため weak。
    /// SidebarNavigator+History.swift の履歴適用からも参照するため internal。
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
        resolveGitRoot: @escaping @Sendable (URL) async -> URL? = { _ in nil },
        loadGitStatuses: @escaping (URL, GitStatusRefreshPolicy) async -> GitStatusResult
            = { _, _ in .empty },
        makeGitIndexWatcher: @escaping GitIndexWatch.WatcherFactory
            = { url, onChange in FileWatcher(path: url, onChange: onChange) }
    ) {
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.directoryLister = directoryLister
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
            fileListModel: fileListModel, resolveGitRoot: resolveGitRoot
        )
        gitStatus = SidebarGitStatusCoordinator(
            fileListModel: fileListModel,
            loadGitStatuses: loadGitStatuses,
            makeGitIndexWatcher: makeGitIndexWatcher
        )
        syncDisplayPreferences()
        baseDirectory.refresh()
    }

    // MARK: - Git Status

    /// 表示中ディレクトリの git 状態を取り直して fileListModel へ反映する。
    /// 実処理は SidebarGitStatusCoordinator が持つ。
    /// - Parameter policy: `.onlyIfIndexChanged` は `.git/index` が動いていないとき git を起こさない
    ///   (`.git` 配下の書き込み通知が契機のとき用)。それ以外の契機では `.always` を使うこと。
    func refreshGitStatuses(policy: GitStatusRefreshPolicy = .always) {
        gitStatus.refresh(policy: policy)
    }

    /// 直近に発行した git 状態取得タスク。テストから完了を待つための読み取り専用の窓。
    ///
    /// **絞り込み ON のときの反映はここには載らない**(一覧タスクの中で起きる /
    /// TASK-293)。ON の完了を待つテストは `pendingListingTask` を待つこと。
    var pendingGitStatusTask: Task<Void, Never>? {
        gitStatus.pendingTask
    }

    /// 直近に発行した基準ディレクトリ解決タスク。テストから完了を待つための読み取り専用の窓。
    var pendingBaseDirectoryTask: Task<Void, Never>? {
        baseDirectory.pendingTask
    }

    /// fileListModel 側の表示設定ミラーを真実の源(sidebarDisplayPreference)へ同期し、
    /// showHiddenFiles を返す(DirectoryLister 呼び出し前後の重複読み取りを避けるため)。
    /// 「変更ファイルのみ表示」のトグルは applyChangedFilesOnlyToggle() を使うこと。
    @discardableResult
    func syncDisplayPreferences() -> Bool {
        let showHiddenFiles = sidebarDisplayPreference.showHiddenFiles
        fileListModel.showHiddenFiles = showHiddenFiles
        fileListModel.showChangedFilesOnly = sidebarDisplayPreference.showChangedFilesOnly
        fileListModel.layoutMode = sidebarDisplayPreference.layoutMode
        return showHiddenFiles
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
    /// git 状態の反映通知先も同じ host なので、ここで一緒に結線する。
    func attach(to host: SidebarNavigatorHost) {
        self.host = host
        gitStatus.attach(to: host)
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

    // MARK: - File List

    /// サイドバーのファイル一覧を現在のディレクトリで取り直し、現在ファイルを選択する。
    /// 列挙はメイン外で行い、完了後にメインアクターへ一括反映する(呼び出し自体は非 async)。
    /// - Parameter applyCustomSelection: 一覧反映後(fileListModel.entries 更新後)に呼ばれる。
    ///   選択を自前で決めて true を返すと既定の選択保持/フォールバック処理をスキップする。
    ///   false を返すと既定処理にフォールバックする。applyHistoryEntry の
    ///   「上へ移動」後の親フォルダ選択復元に使う。
    func refreshFileList(applyCustomSelection: (() -> Bool)? = nil) {
        guard host != nil else { return }
        performListing(of: fileListModel.currentDirectory) { host, directory, listing in
            let entries = self.applyRows(
                listing.appendingOpenFile(host.currentFileURL, in: directory), for: directory
            )

            if let applyCustomSelection, applyCustomSelection() {
                return
            }

            // 既存の選択(フォルダーも含む)が一覧内に残っていればそのまま保持する。
            // フォルダー選択時は currentFileURL と一致しない状態が正当にあり得るため、
            // ここで currentFileURL への一致を強制してはならない(issue #161)。
            let selectionStillValid = self.fileListModel.selection.map { selection in
                let selectionKey = selection.normalizedPathKey
                return entries.contains { $0.pathKey == selectionKey }
            } ?? false
            guard !selectionStillValid else { return }
            self.fileListModel.selection = self.fileListModel.matchingEntryURL(for: host.currentFileURL)
        }
    }

    /// 世代ガード付きの一覧取得パイプライン。refreshFileList / navigateToFolder が共有する。
    /// 「基準ディレクトリ更新 → 不可視ファイル設定同期 → 世代更新 → メイン外で列挙と git 状態取得 →
    /// 世代・host guard」までを担い、一覧の反映と選択の決定は onApplied に委ねる。
    ///
    /// 絞り込み(showChangedFilesOnly)が ON のときは、一覧と git 状態を **同じタスクで並行に
    /// 取り、同じメインアクター実行で一緒に反映する**。別タスクに分けると完了順が保証されず、
    /// 新しいディレクトリの一覧だけが先に描画される間だけ絞り込みが縮退して(状態が別
    /// ディレクトリのものなので絞り込まない)、全件が一瞬見えてから絞り込まれる(TASK-293)。
    ///
    /// OFF のときは揃える理由が無い(絞り込まないので縮退しようがなく、git 状態はバッジに
    /// しか効かない)。それでも待つと、絞り込みを使っていない利用者までフォルダー移動・
    /// フォーカス復帰・ソート変更のたびに git subprocess の完了を待たされるため、一覧は
    /// 列挙が終わり次第反映し、git 状態は単発取得と同じ世代ガードで遅れて反映する(TASK-297)。
    /// - Parameters:
    ///   - directory: 列挙対象のディレクトリ。
    ///   - onApplied: 列挙結果が最新世代かつ host が生存しているときにメインアクターで呼ばれる。
    ///     列挙対象のディレクトリを一緒に渡すため、呼び出し元は `fileListModel.currentDirectory`
    ///     の現在値を読み直さずに `FileListModel.setEntries(_:for:)` へそのまま渡せる(TASK-298)。
    /// SidebarNavigator+FolderNavigation.swift からも呼ぶため internal。
    func performListing(
        of directory: URL,
        onApplied: @escaping @MainActor (SidebarNavigatorHost, URL, DirectoryListing) -> Void
    ) {
        baseDirectory.refresh()
        let showHiddenFiles = syncDisplayPreferences()
        // ルートを取り直す契機(並び順の変更・隠しファイルのトグル・フォーカス復帰・リネーム)は
        // そのまま展開中サブツリーを取り直す契機でもある。ここを通さないと、展開したフォルダの
        // 中だけが古い並び順・古い隠しファイル設定のまま残る。
        tree.reloadExpandedChildren()
        let couplesGitStatus = fileListModel.showChangedFilesOnly
        let sortOrder = fileListModel.sortOrder
        listingGeneration += 1
        let generation = listingGeneration
        // 先に git 側のタスクを起こしてから列挙を待つ。どちらも本体は nonisolated async で
        // 走るため、待ち時間は直列にならず遅いほうに揃う。採番は券の内側に閉じている。
        let request = gitStatus.beginListingRequest(for: directory)
        let task = Task {
            let listing = await self.directoryLister(directory, sortOrder, showHiddenFiles)
            let result = couplesGitStatus ? await self.gitStatus.awaitResult(request) : nil
            guard generation == self.listingGeneration, let host = self.host else { return }
            if let result {
                // 最新の一覧と対の結果なので、待ち合わせ中に単発 refreshGitStatuses が
                // 番号を進めていても、まだ何も反映されていなければ捨ててはならない
                // (捨てると絞り込みが外れる / TASK-294)。一方で番号を偽って進めもしない。
                // 単発の新しい結果が先に着いていれば、そちらのほうが一覧と対にふさわしい。
                //
                // **この guard を挟むために待ちと反映が 2 本の API に分かれている。**
                // 融合すると一覧世代が古いときでも結果が FileListModel まで届く。
                self.gitStatus.apply(result, for: request)
            }
            onApplied(host, directory, listing)
        }
        pendingListingTask = task
        // 絞り込み ON の反映は上のタスクの中で起きるので、ここでは何もしない
        // (待ちたいテストは pendingListingTask を待つ)。OFF のときだけ、一覧と
        // 切り離した反映を coordinator に任せる。
        if !couplesGitStatus {
            gitStatus.applyWhenReady(request)
        }
    }

    /// 進行中の一覧取得タスクを破棄する。ウィンドウを閉じるときに呼ぶ。
    /// キャンセルは協調的で、走り出した subprocess は完了して結果を返しうる。世代を進めておかないと
    /// その結果が反映ガードを通り抜け、閉じたウィンドウのために `.git/index` 監視を張り直す
    /// (以後リポジトリを触るたび git が起動し続ける / TASK-300)。
    func cancelPendingListing() {
        listingGeneration += 1
        pendingListingTask?.cancel()
        pendingListingTask = nil
        // 協力型が持つ進行中の処理は、それぞれの型の 1 メソッドへ畳んである。
        // ここに個別の世代加算や pending の nil 代入が戻ってきたら、分離が崩れている。
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
