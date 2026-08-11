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
    /// ツリー展開の状態と、展開したフォルダの子リスト。
    ///
    /// **注入引数にしない。** デフォルト引数で外から渡せる形にすると、渡し忘れが
    /// コンパイルエラーにならず静かに別インスタンスになる(TASK-319 と同型)。
    /// ウィンドウごとに 1 つという粒度を、生成箇所をここ 1 つに固定することで守る。
    let expansion = SidebarExpansion()
    /// 展開したフォルダの子リストの取得元。ルートの一覧(directoryLister)とは
    /// **別の関数**であることが要点で、あちらは親移動行を別に持つルート一覧の材料を返す。
    /// SidebarNavigator+Expansion.swift から参照するため internal。
    /// 子リストの列挙。**nil は列挙失敗**(空のフォルダの `[]` と区別する)。
    let childrenLister: (URL, SortOrder, Bool) async -> [FileListEntry]?
    /// refreshFileList / navigateToFolder が発行する一覧取得タスクの世代番号。
    /// 新しい要求が来たら古い結果の反映を捨てる(ViewerStore.loadGeneration と同型)。
    private var listingGeneration = 0
    /// 直近に `applyRows` へ渡した列挙結果。行を組み直すたびに組み立て済みの配列から
    /// 材料を復元しないために持つ。**書いてよいのは `applyRows` だけ**(他所から書くと、
    /// 世代ガードを通っていない古い列挙で `rebuildRows` が走る)。別ファイルの extension が
    /// 書くため `private(set)` にはできない。
    var lastListing = DirectoryListing.empty
    /// 直近に発行した一覧取得タスク。テストから完了を待つために公開する。
    private(set) var pendingListingTask: Task<Void, Never>?
    /// 現在のディレクトリが属する git リポジトリの作業ツリールート。git 管理外なら nil。
    /// 未命中時に `git rev-parse` の subprocess を待つため async にし、
    /// メインスレッド(SwiftUI の body 評価)で解決しないようにしている。
    private let resolveGitRoot: @Sendable (URL) async -> URL?
    /// baseDirectory 更新タスクの世代番号。一覧取得(listingGeneration)とは
    /// 完了タイミングが独立するため、別の世代で古い結果を捨てる。
    private var baseDirectoryGeneration = 0
    /// 直近に発行した基準ディレクトリ解決タスク。テストから完了を待つために公開する。
    private(set) var pendingBaseDirectoryTask: Task<Void, Never>?
    /// 表示中ディレクトリのファイルに対する git 状態を取得する。既定は常に空(機能無効)。
    /// git 型に直接依存しないよう、`resolveGitRoot` と同型のクロージャで注入する。
    private let loadGitStatuses: (URL, GitStatusRefreshPolicy) async -> GitStatusResult
    /// `.git/index` の監視。対象パスの管理は GitIndexWatch が持つ。
    /// init で self を渡せないため、attach 前の最初の取得までに解決できるよう遅延で作る。
    private lazy var gitIndexWatch = GitIndexWatch(makeWatcher: makeGitIndexWatcher) { [weak self] in
        self?.refreshGitStatuses(policy: .onlyIfIndexChanged)
    }

    /// `.git/index` を監視するウォッチャの生成器。既定は実 FileWatcher。
    /// テストは実ファイルシステム監視を避けるため差し替える。
    private let makeGitIndexWatcher: GitIndexWatch.WatcherFactory
    /// git 状態取得タスクの発行順序(sequence)の採番器。一覧取得・基準ディレクトリ解決とは完了
    /// タイミングが独立する(subprocess の所要時間が別)ため、第 3 の世代として分けて発行する。
    /// 反映の可否判定(recency ガード)は持たず、採番だけを担う(ADR 0003)。
    private var gitStatusGeneration = 0
    /// 直近に発行した git 状態取得タスク。テストから完了を待つために公開する。
    private(set) var pendingGitStatusTask: Task<Void, Never>?

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
        self.makeGitIndexWatcher = makeGitIndexWatcher
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.directoryLister = directoryLister
        self.childrenLister = childrenLister
        self.resolveGitRoot = resolveGitRoot
        self.loadGitStatuses = loadGitStatuses
        fileListModel = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection,
            sortOrder: sortOrder
        )
        syncDisplayPreferences()
        refreshBaseDirectory()
    }

    // MARK: - Base Directory

    /// 相対パスコピー・Quick Open の基準ディレクトリを取り直して fileListModel へ反映する。
    /// git ルートの解決はメイン外で行い、完了後にメインアクターへ戻して書き込む。
    /// ディレクトリが変わる契機(初期化・一覧更新・フォルダ移動)ごとに呼ぶ。
    private func refreshBaseDirectory() {
        let directory = fileListModel.currentDirectory
        let workspaceRoot = fileListModel.rootDirectory
        baseDirectoryGeneration += 1
        let generation = baseDirectoryGeneration
        pendingBaseDirectoryTask = Task {
            let gitRoot = await self.resolveGitRoot(directory)
            guard generation == self.baseDirectoryGeneration else { return }
            self.fileListModel.baseDirectory = BaseDirectoryDescriptor(
                gitRoot: gitRoot,
                workspaceRoot: workspaceRoot
            )
        }
    }

    // MARK: - Git Status

    /// 表示中ディレクトリの git 状態を取り直して fileListModel へ反映する。取得(ルート解決 +
    /// git 実行)はメイン外で行う。機能が無効なら注入クロージャが常に空を返すため git は起動しない。
    /// - Parameter policy: `.onlyIfIndexChanged` は `.git/index` が動いていないとき git を起こさない
    ///   (`.git` 配下の書き込み通知が契機のとき用)。それ以外の契機では `.always` を使うこと。
    func refreshGitStatuses(policy: GitStatusRefreshPolicy = .always) {
        let directory = fileListModel.currentDirectory
        gitStatusGeneration += 1
        let generation = gitStatusGeneration
        pendingGitStatusTask = Task {
            let result = await self.loadGitStatuses(directory, policy)
            self.applyGitStatus(result, for: directory, generation: generation)
        }
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
    func attach(to host: SidebarNavigatorHost) {
        self.host = host
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
            self.fileListModel.selection = self.matchingEntryURL(for: host.currentFileURL)
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
        refreshBaseDirectory()
        let showHiddenFiles = syncDisplayPreferences()
        // ルートを取り直す契機(並び順の変更・隠しファイルのトグル・フォーカス復帰・リネーム)は
        // そのまま展開中サブツリーを取り直す契機でもある。ここを通さないと、展開したフォルダの
        // 中だけが古い並び順・古い隠しファイル設定のまま残る。
        reloadExpandedChildren()
        let couplesGitStatus = fileListModel.showChangedFilesOnly
        let sortOrder = fileListModel.sortOrder
        listingGeneration += 1
        gitStatusGeneration += 1
        let generation = listingGeneration
        let gitGeneration = gitStatusGeneration
        // 先に git 側のタスクを起こしてから列挙を待つ。どちらも本体は nonisolated async で
        // 走るため、待ち時間は直列にならず遅いほうに揃う。
        let gitTask = Task { await self.loadGitStatuses(directory, .always) }
        let task = Task {
            let listing = await self.directoryLister(directory, sortOrder, showHiddenFiles)
            let result = couplesGitStatus ? await Self.awaitingCancellable(gitTask) : nil
            guard generation == self.listingGeneration, let host = self.host else { return }
            if let result {
                // 最新の一覧と対の結果なので、待ち合わせ中に単発 refreshGitStatuses が世代を
                // 進めていても、まだ何も反映されていなければ捨ててはならない
                // (捨てると絞り込みが外れる / TASK-294)。一方で世代を偽って進めもしない。
                // 単発の新しい結果が先に着いていれば、そちらのほうが一覧と対にふさわしい。
                self.applyGitStatus(result, for: directory, generation: gitGeneration)
            }
            onApplied(host, directory, listing)
        }
        pendingListingTask = task
        // git 状態の待ち合わせ点。ON なら一覧タスクに含まれるのでそれ自体を、OFF なら
        // 一覧と切り離した反映タスクを公開する(一覧より遅れて着地しても FileListModel の
        // 保留機構が一覧と突き合わせるため、先着後着どちらでも整合は崩れない)。
        pendingGitStatusTask = couplesGitStatus ? task : Task {
            let result = await Self.awaitingCancellable(gitTask)
            self.applyGitStatus(result, for: directory, generation: gitGeneration)
        }
    }

    /// git 取得タスクの完了を待つ。待ち側のキャンセル(ウィンドウを閉じたとき)を
    /// 取得側へも伝えるため、素の `await task.value` ではなくこちらを通す。
    private static func awaitingCancellable(
        _ task: Task<GitStatusResult, Never>
    ) async -> GitStatusResult {
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    /// 取得した git 状態を FileListModel へ渡す。反映の可否(発行順序・ディレクトリ対付け)は
    /// FileListModel.applyGitStatus が一括判定する(ADR 0003)。受け付けられたときだけ
    /// index の監視対象を合わせる(古い結果で監視を張り直してはならない)。
    private func applyGitStatus(
        _ result: GitStatusResult, for directory: URL, generation: Int
    ) {
        let accepted = fileListModel.applyGitStatus(
            SidebarGitStatus(result: result), for: directory, sequence: generation
        )
        guard accepted else { return }
        gitIndexWatch.update(indexURL: result.indexURL)
        // バッジが動いたら、同じ契機で表示中ファイルの差分も取り直す。
        // 捨てられた(accepted == false)のは「より新しい結果が既に反映済み」のときだけで、
        // その結果自身がここを通っているため取り残しは起きない。
        host?.gitStatusDidApply()
    }

    /// 進行中の一覧取得タスクを破棄する。ウィンドウを閉じるときに呼ぶ。
    /// キャンセルは協調的で、走り出した subprocess は完了して結果を返しうる。世代を進めておかないと
    /// その結果が反映ガードを通り抜け、閉じたウィンドウのために `.git/index` 監視を張り直す
    /// (以後リポジトリを触るたび git が起動し続ける / TASK-300)。
    func cancelPendingListing() {
        listingGeneration += 1
        gitStatusGeneration += 1
        // 反映済み sequence を発行済みの先頭へ揃えることで、進行中の取得を一括で無効化する
        // (FileListModel 側で「反映済みより新しい」ものだけを通すため / ADR 0003, 元 TASK-299)。
        fileListModel.invalidatePendingGitStatus(upTo: gitStatusGeneration)
        baseDirectoryGeneration += 1
        pendingListingTask?.cancel()
        pendingListingTask = nil
        pendingBaseDirectoryTask?.cancel()
        pendingBaseDirectoryTask = nil
        pendingGitStatusTask?.cancel()
        pendingGitStatusTask = nil
        // 展開の子リスト取得も無効化する。ここを忘れると、閉じたウィンドウのために
        // 走行中だった列挙が着地して状態を書き続ける(TASK-300 と同型)。
        expansion.invalidateAll()
        gitIndexWatch.stop()
    }

    /// エントリ一覧からフォルダーの正規化キーが一致するものを返す。
    /// SidebarNavigator+History.swift の履歴適用からも参照するため internal。
    func folderEntryURL(forKey key: String) -> URL? {
        fileListModel.entries.first {
            $0.kind == .folder && $0.pathKey == key
        }?.url
    }

    /// エントリ一覧から URL の正規化キーが一致するものを探し、
    /// 見つからなければ元の URL をそのまま返す。
    func matchingEntryURL(for url: URL) -> URL {
        let key = url.normalizedPathKey
        return fileListModel.entries.first {
            $0.pathKey == key
        }?.url ?? url
    }

    /// switchFile 成功後にサイドバー選択を同期し、履歴を記録する。
    /// ViewerWindowController.switchFile がファイル切替の実処理後に呼ぶ。
    func syncAfterSwitch(to newURL: URL) {
        let newDir = newURL.deletingLastPathComponent().normalizedPathKey
        if newDir != fileListModel.currentDirectory.normalizedPathKey {
            fileListModel.currentDirectory = newURL.deletingLastPathComponent()
            refreshFileList()
        } else {
            fileListModel.selection = matchingEntryURL(for: newURL)
        }
        recordHistory()
    }

    /// ファイル切替が別ウィンドウ移譲・失敗で成立しなかったときに選択を元へ戻す。
    func restoreSelection(to url: URL) {
        fileListModel.selection = url
    }
}
