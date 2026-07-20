import Foundation

/// SidebarNavigator がファイル切替・現在ファイル参照を委譲する先。
/// ViewerWindowController が実装する。循環参照を避けるため SidebarNavigator からは weak 参照する。
@MainActor
protocol SidebarNavigatorHost: AnyObject {
    /// 現在表示中のファイル URL。performFileSwitch により変化するため都度参照する。
    var currentFileURL: URL { get }
    /// サイドバー選択・履歴から要求されたファイル切替の実処理。成功時 true。
    @discardableResult
    func performFileSwitch(to url: URL) -> Bool
    /// 別ファイルへの完全なファイル切替(別ウィンドウ判定・選択同期・履歴記録込み)。
    /// サイドバー/フォルダー一覧でのファイル選択やリンク参照など、ファイルを明示的に
    /// 選んだ操作から呼ばれる(フォルダ移動時の自動オープンには使わない)。
    func switchFile(to url: URL)
    /// 指定 URL が自分以外のウィンドウで既に開かれているか。
    func isFileOpenElsewhere(_ url: URL) -> Bool
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

    /// ファイル切替・現在ファイル参照の委譲先。循環参照を避けるため weak。
    private weak var host: SidebarNavigatorHost?

    // MARK: - Initialization

    init(
        currentDirectory: URL, entries: [FileListEntry], selection: URL?,
        hiddenFilesPreference: HiddenFilesPreference,
        sortOrder: SortOrder = .foldersFirst,
        directoryLister: @escaping (URL, SortOrder, Bool) async -> [FileListEntry]
            = DirectoryLister.listEntriesAsync
    ) {
        self.hiddenFilesPreference = hiddenFilesPreference
        self.directoryLister = directoryLister
        fileListModel = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection,
            sortOrder: sortOrder
        )
        syncShowHiddenFiles()
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
        let showHiddenFiles = syncShowHiddenFiles()
        let directory = fileListModel.currentDirectory
        let sortOrder = fileListModel.sortOrder
        listingGeneration += 1
        let generation = listingGeneration
        pendingListingTask = Task {
            var entries = await self.directoryLister(directory, sortOrder, showHiddenFiles)
            guard generation == self.listingGeneration, let host = self.host else { return }
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
                return entries.contains { $0.url.normalizedPathKey == selectionKey }
            } ?? false
            guard !selectionStillValid else { return }
            self.fileListModel.selection = self.matchingEntryURL(for: host.currentFileURL)
        }
    }

    /// 進行中の一覧取得タスクを破棄する。ウィンドウを閉じるときに呼ぶ。
    func cancelPendingListing() {
        pendingListingTask?.cancel()
        pendingListingTask = nil
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
        if !entries.contains(where: { $0.url.normalizedPathKey == key }) {
            entries.append(FileListEntry(url: currentFile, kind: .file))
        }
    }

    /// エントリ一覧からフォルダーの正規化キーが一致するものを返す。
    private func folderEntryURL(forKey key: String) -> URL? {
        fileListModel.entries.first {
            $0.kind == .folder && $0.url.normalizedPathKey == key
        }?.url
    }

    /// エントリ一覧から URL の正規化キーが一致するものを探し、
    /// 見つからなければ元の URL をそのまま返す。
    func matchingEntryURL(for url: URL) -> URL {
        let key = url.normalizedPathKey
        return fileListModel.entries.first {
            $0.url.normalizedPathKey == key
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
        let showHiddenFiles = syncShowHiddenFiles()
        let sortOrder = fileListModel.sortOrder
        listingGeneration += 1
        let generation = listingGeneration
        pendingListingTask = Task {
            let entries = await self.directoryLister(url, sortOrder, showHiddenFiles)
            guard generation == self.listingGeneration, self.host != nil else { return }
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
        if let file = entry.file,
           file.normalizedPathKey != host.currentFileURL.normalizedPathKey,
           host.isFileOpenElsewhere(file)
        {
            return false
        }
        let dirChanged = entry.directory.normalizedPathKey
            != fileListModel.currentDirectory.normalizedPathKey
        // ファイル切替が存在しないファイルで失敗すると performFileSwitch が false を返す。
        // currentDirectory の書き換えより先に切替を試み、失敗時は状態を一切変えずに
        // return して部分適用による不整合(dir だけ変わって file list 未更新)を防ぐ。
        if let file = entry.file,
           file.normalizedPathKey != host.currentFileURL.normalizedPathKey
        {
            guard host.performFileSwitch(to: file) else { return false }
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
