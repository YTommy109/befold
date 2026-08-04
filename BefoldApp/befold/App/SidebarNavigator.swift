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
    /// 不可視ファイル表示設定。全ウィンドウで共有される単一の真実の源を都度参照する。
    private let sidebarDisplayPreference: SidebarDisplayPreference
    /// ファイル一覧の再取得元。既定は DirectoryLister.listEntriesAsync(nonisolated async)だが、
    /// 再読込経路をテストで差し替えられるよう注入可能にする。async のため呼び出し元アクター
    /// (MainActor)を離れて実行され、巨大ディレクトリでもメインスレッドを塞がない。
    private let directoryLister: (URL, SortOrder, Bool) async -> [FileListEntry]
    /// refreshFileList / navigateToFolder が発行する一覧取得タスクの世代番号。
    /// 新しい要求が来たら古い結果の反映を捨てる(ViewerStore.loadGeneration と同型)。
    private var listingGeneration = 0
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
    private let makeGitIndexWatcher: (URL, @escaping @MainActor @Sendable () -> Void) -> FileWatching
    /// git 状態取得タスクの世代番号。一覧取得・基準ディレクトリ解決とは完了タイミングが
    /// 独立する(subprocess の所要時間が別)ため、第 3 の世代として分けて古い結果を捨てる。
    private var gitStatusGeneration = 0
    /// 直近に発行した git 状態取得タスク。テストから完了を待つために公開する。
    private(set) var pendingGitStatusTask: Task<Void, Never>?

    /// ファイル切替・現在ファイル参照の委譲先。循環参照を避けるため weak。
    private weak var host: SidebarNavigatorHost?

    // MARK: - Initialization

    init(
        currentDirectory: URL, entries: [FileListEntry], selection: URL?,
        sidebarDisplayPreference: SidebarDisplayPreference,
        sortOrder: SortOrder = .foldersFirst,
        directoryLister: @escaping (URL, SortOrder, Bool) async -> [FileListEntry]
            = DirectoryLister.listEntriesAsync,
        resolveGitRoot: @escaping @Sendable (URL) async -> URL? = { _ in nil },
        loadGitStatuses: @escaping (URL, GitStatusRefreshPolicy) async -> GitStatusResult
            = { _, _ in .empty },
        makeGitIndexWatcher: @escaping (URL, @escaping @MainActor @Sendable () -> Void) -> FileWatching
            = { url, onChange in FileWatcher(path: url, onChange: onChange) }
    ) {
        self.makeGitIndexWatcher = makeGitIndexWatcher
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.directoryLister = directoryLister
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
        return showHiddenFiles
    }

    /// 「変更ファイルのみ表示」トグル時に呼ぶ。表示述語を同期し、git 状態だけ取り直す(再列挙はしない)。
    /// 作業ツリーの編集は index も windowDidBecomeKey も動かさず、古い状態で絞り込まれるため(TASK-296)。
    func applyChangedFilesOnlyToggle() {
        syncDisplayPreferences()
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
        performListing(of: fileListModel.currentDirectory) { host, entries in
            var entries = entries
            self.ensureCurrentFile(in: &entries, currentFile: host.currentFileURL)
            self.fileListModel.entries = entries

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
    private func performListing(
        of directory: URL,
        onApplied: @escaping @MainActor (SidebarNavigatorHost, [FileListEntry]) -> Void
    ) {
        refreshBaseDirectory()
        let showHiddenFiles = syncDisplayPreferences()
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
            let entries = await self.directoryLister(directory, sortOrder, showHiddenFiles)
            let result = couplesGitStatus ? await Self.awaitingCancellable(gitTask) : nil
            guard generation == self.listingGeneration, let host = self.host else { return }
            if let result {
                // 最新の一覧と対の結果なので、待ち合わせ中に単発 refreshGitStatuses が世代を
                // 進めていても捨ててはならない(捨てると絞り込みが外れる / TASK-294)。
                self.gitStatusGeneration += 1
                self.applyGitStatus(result, for: directory, generation: self.gitStatusGeneration)
            }
            onApplied(host, entries)
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

    /// 取得した git 状態を最新世代のときだけ反映し、index の監視対象を合わせる。
    private func applyGitStatus(
        _ result: GitStatusResult, for directory: URL, generation: Int
    ) {
        guard generation == gitStatusGeneration else { return }
        fileListModel.applyGitStatus(
            SidebarGitStatus(directory: directory, result: result), for: directory
        )
        gitIndexWatch.update(indexURL: result.indexURL)
    }

    /// 進行中の一覧取得タスクを破棄する。ウィンドウを閉じるときに呼ぶ。
    func cancelPendingListing() {
        pendingListingTask?.cancel()
        pendingListingTask = nil
        pendingBaseDirectoryTask?.cancel()
        pendingBaseDirectoryTask = nil
        pendingGitStatusTask?.cancel()
        pendingGitStatusTask = nil
        gitIndexWatch.stop()
    }

    /// エントリ一覧に現在のファイルが含まれていなければ末尾に追加する。
    /// 規則そのものは DirectoryLister.appendingOpenFile に置き、プレビューの
    /// フォルダー一覧と同じ実装を共有する(TASK-295)。
    private func ensureCurrentFile(in entries: inout [FileListEntry], currentFile: URL) {
        entries = DirectoryLister.appendingOpenFile(
            currentFile, to: entries, in: fileListModel.currentDirectory
        )
    }

    /// エントリ一覧からフォルダーの正規化キーが一致するものを返す。
    private func folderEntryURL(forKey key: String) -> URL? {
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

    // MARK: - Folder Navigation

    /// サイドバーで別フォルダーへ移動する。ホームディレクトリ配下のみ許可する。
    /// 列挙はメイン外で行い、完了後にメインアクターへ一括反映する(呼び出し自体は非 async)。
    /// 移動先に最初から自動的にファイルを開くことはしない(#folder-preview-listing)。
    /// 選択を空にすることで、プレビューエリアには新しいディレクトリの一覧が表示される
    /// (PreviewTargetResolver.resolve が selection == nil を currentDirectory の一覧として扱う)。
    func navigateToFolder(_ url: URL) {
        guard host != nil else { return }
        let target = url.standardizedFileURL
        guard DirectoryLister.isWithinHome(target) else { return }
        let previous = fileListModel.currentDirectory
        fileListModel.currentDirectory = url
        updateRootDirectory(with: target)
        performListing(of: url) { _, entries in
            self.fileListModel.entries = entries
            let isGoingUp = target.normalizedPathKey == previous.deletingLastPathComponent()
                .normalizedPathKey
            if isGoingUp {
                self.fileListModel.selection = self.folderEntryURL(forKey: previous.normalizedPathKey)
            } else {
                self.fileListModel.selection = nil
            }
            self.recordHistory()
        }
    }

    /// このウィンドウでこれまでにアクティブになった最上位のディレクトリ(rootDirectory)を更新する。
    /// target が rootDirectory の祖先(より上位)なら、そこを新たな最上位として記録する。
    /// 既に到達した最上位より下位・並列のディレクトリへ移動しても rootDirectory は変えない。
    private func updateRootDirectory(with target: URL) {
        let rootKey = fileListModel.rootDirectory.normalizedPathKey
        let targetKey = target.normalizedPathKey
        let rootComponents = rootKey.split(separator: "/")
        let targetComponents = targetKey.split(separator: "/")
        guard targetComponents.count < rootComponents.count,
              rootComponents.starts(with: targetComponents)
        else { return }
        fileListModel.rootDirectory = target
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

// MARK: - Navigation History

/// 戻る/進む履歴の記録と適用。一覧・git 状態の取得とは独立した関心事なので
/// 本体から切り出す(NavigationHistory と fileListModel/host の橋渡しだけを担う)。
@MainActor
extension SidebarNavigator {
    /// サイドバーの戻る/進む・履歴メニューから呼ばれる。offset 負=戻る / 正=進む。
    func navigateHistory(by offset: Int) {
        guard let entry = history.move(by: offset) else { return }
        if !applyHistoryEntry(entry) {
            _ = history.move(by: -offset)
        }
        refreshHistoryState()
    }

    /// 現在の表示状態(ディレクトリ＋ファイル)を履歴に記録する。
    /// push は現在エントリと同一なら無視する。
    func recordHistory() {
        guard let host else { return }
        history.push(HistoryEntry(directory: fileListModel.currentDirectory, file: host.currentFileURL))
        refreshHistoryState()
    }

    /// 履歴エントリを表示へ適用する。適用できなかった場合は false を返す。
    @discardableResult
    private func applyHistoryEntry(_ entry: HistoryEntry) -> Bool {
        guard let host else { return false }
        let dirChanged = entry.directory.normalizedPathKey
            != fileListModel.currentDirectory.normalizedPathKey
        // 存在しないファイルへは切替できず performFileSwitch が .failed を返す。
        // currentDirectory の書き換えより先に切替を試み、失敗時は状態を一切変えずに
        // return して部分適用による不整合(dir だけ変わって file list 未更新)を防ぐ。
        // 別ウィンドウが同じファイルを開いていても自ウィンドウで切り替える(他ウィンドウの
        // 前面化はしない)。利用者はこのウィンドウの履歴を辿っているだけなので奪わない。
        if let file = entry.file,
           file.normalizedPathKey != host.currentFileURL.normalizedPathKey
        {
            guard case .switched = host.performFileSwitch(to: file) else { return false }
        }
        if dirChanged {
            fileListModel.currentDirectory = entry.directory
            // ファイルがディレクトリ外(上へ移動で記録されたエントリ)の場合、
            // ファイルの親フォルダを選択して元の状態を復元する(一覧反映後に判定する)。
            let fileDir = host.currentFileURL.deletingLastPathComponent().normalizedPathKey
            refreshFileList { [weak self] in
                guard let self, fileDir != fileListModel.currentDirectory.normalizedPathKey else { return false }
                fileListModel.selection = folderEntryURL(forKey: fileDir)
                return true
            }
        } else {
            fileListModel.selection = matchingEntryURL(for: host.currentFileURL)
        }
        return true
    }

    /// rename/move を履歴へ反映し、履歴状態を更新する。
    func applyRename(from oldURL: URL, to newURL: URL) {
        history.renameOccurred(from: oldURL, to: newURL)
        refreshHistoryState()
    }

    /// 履歴状態をサイドバー(FileListModel)とホスト(ツールバー)へ反映する。
    private func refreshHistoryState() {
        fileListModel.backHistory = history.backEntries()
        fileListModel.forwardHistory = history.forwardEntries()
        host?.historyStateDidChange()
    }
}
