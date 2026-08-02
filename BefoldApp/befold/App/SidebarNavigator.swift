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
    private let hiddenFilesPreference: HiddenFilesPreference
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
    private let loadGitStatuses: (URL) async -> [String: GitFileStatus]
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
        hiddenFilesPreference: HiddenFilesPreference,
        sortOrder: SortOrder = .foldersFirst,
        directoryLister: @escaping (URL, SortOrder, Bool) async -> [FileListEntry]
            = DirectoryLister.listEntriesAsync,
        resolveGitRoot: @escaping @Sendable (URL) async -> URL? = { _ in nil },
        loadGitStatuses: @escaping (URL) async -> [String: GitFileStatus] = { _ in [:] }
    ) {
        self.hiddenFilesPreference = hiddenFilesPreference
        self.directoryLister = directoryLister
        self.resolveGitRoot = resolveGitRoot
        self.loadGitStatuses = loadGitStatuses
        fileListModel = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection,
            sortOrder: sortOrder
        )
        syncShowHiddenFiles()
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

    /// 表示中ディレクトリの git 状態を取り直して fileListModel へ反映する。
    /// 取得(ルート解決 + git 実行)はメイン外で行い、完了後にメインアクターへ戻して書き込む。
    /// 機能が無効なら注入クロージャが常に空を返すため、git は起動しない。
    private func refreshGitStatuses() {
        let directory = fileListModel.currentDirectory
        gitStatusGeneration += 1
        let generation = gitStatusGeneration
        pendingGitStatusTask = Task {
            let statuses = await self.loadGitStatuses(directory)
            guard generation == self.gitStatusGeneration else { return }
            self.fileListModel.gitStatuses = statuses
        }
    }

    /// fileListModel.showHiddenFiles を真実の源(hiddenFilesPreference)へ同期し、
    /// 同期後の値を返す。DirectoryLister 呼び出し前後の重複読み取りを避けるため、
    /// この値を呼び出し側で再利用する。
    @discardableResult
    private func syncShowHiddenFiles() -> Bool {
        let showHiddenFiles = hiddenFilesPreference.showHiddenFiles
        fileListModel.showHiddenFiles = showHiddenFiles
        return showHiddenFiles
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
    /// 「基準ディレクトリ更新 → 不可視ファイル設定同期 → 世代更新 → メイン外で列挙 →
    /// 世代・host guard」までを担い、一覧の反映と選択の決定は onApplied に委ねる。
    /// - Parameters:
    ///   - directory: 列挙対象のディレクトリ。
    ///   - onApplied: 列挙結果が最新世代かつ host が生存しているときにメインアクターで呼ばれる。
    private func performListing(
        of directory: URL,
        onApplied: @escaping @MainActor (SidebarNavigatorHost, [FileListEntry]) -> Void
    ) {
        refreshBaseDirectory()
        refreshGitStatuses()
        let showHiddenFiles = syncShowHiddenFiles()
        let sortOrder = fileListModel.sortOrder
        listingGeneration += 1
        let generation = listingGeneration
        pendingListingTask = Task {
            let entries = await self.directoryLister(directory, sortOrder, showHiddenFiles)
            guard generation == self.listingGeneration, let host = self.host else { return }
            onApplied(host, entries)
        }
    }

    /// 進行中の一覧取得タスクを破棄する。ウィンドウを閉じるときに呼ぶ。
    func cancelPendingListing() {
        pendingListingTask?.cancel()
        pendingListingTask = nil
        pendingBaseDirectoryTask?.cancel()
        pendingBaseDirectoryTask = nil
        pendingGitStatusTask?.cancel()
        pendingGitStatusTask = nil
    }

    /// エントリ一覧に現在のファイルが含まれていなければ末尾に追加する。
    /// allExtensions に含まれない拡張子(plaintext フォールバック)のファイルが
    /// サイドバーから消える回帰を防ぐ。
    private func ensureCurrentFile(in entries: inout [FileListEntry], currentFile: URL) {
        let dirKey = currentFile.deletingLastPathComponent().normalizedPathKey
        guard dirKey == fileListModel.currentDirectory.normalizedPathKey else {
            return
        }
        let key = currentFile.normalizedPathKey
        if !entries.contains(where: { $0.pathKey == key }) {
            entries.append(FileListEntry(url: currentFile, kind: .file))
        }
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

    // MARK: - Navigation History

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
