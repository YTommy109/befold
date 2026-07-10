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
    /// フォルダ移動で最初のファイルを開くときに使用する。
    func switchFile(to url: URL)
    /// 指定 URL が自分以外のウィンドウで既に開かれているか。
    func isFileOpenElsewhere(_ url: URL) -> Bool
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

    /// ファイル切替・現在ファイル参照の委譲先。循環参照を避けるため weak。
    private weak var host: SidebarNavigatorHost?

    // MARK: - Initialization

    init(
        currentDirectory: URL, entries: [FileListEntry], selection: URL?,
        hiddenFilesPreference: HiddenFilesPreference
    ) {
        self.hiddenFilesPreference = hiddenFilesPreference
        fileListModel = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection
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
    func refreshFileList() {
        guard let host else { return }
        let showHiddenFiles = syncShowHiddenFiles()
        var entries = DirectoryLister.listEntries(
            in: fileListModel.currentDirectory,
            sortOrder: fileListModel.sortOrder,
            showHiddenFiles: showHiddenFiles
        )
        ensureCurrentFile(in: &entries, currentFile: host.currentFileURL)
        fileListModel.entries = entries

        // 既存の選択(フォルダーも含む)が一覧内に残っていればそのまま保持する。
        // フォルダー選択時は currentFileURL と一致しない状態が正当にあり得るため、
        // ここで currentFileURL への一致を強制してはならない(issue #161)。
        let selectionStillValid = fileListModel.selection.map { selection in
            let selectionKey = selection.normalizedPathKey
            return entries.contains { $0.url.normalizedPathKey == selectionKey }
        } ?? false
        guard !selectionStillValid else { return }
        fileListModel.selection = matchingEntryURL(for: host.currentFileURL)
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
    func navigateToFolder(_ url: URL) {
        guard let host else { return }
        let target = url.standardizedFileURL
        guard DirectoryLister.isWithinHome(target) else { return }
        let previous = fileListModel.currentDirectory
        fileListModel.currentDirectory = url
        updateRootDirectory(with: target)
        let showHiddenFiles = syncShowHiddenFiles()
        fileListModel.entries = DirectoryLister.listEntries(
            in: url, sortOrder: fileListModel.sortOrder, showHiddenFiles: showHiddenFiles
        )
        let isGoingUp = target.normalizedPathKey == previous.deletingLastPathComponent()
            .normalizedPathKey
        if isGoingUp {
            let prevKey = previous.normalizedPathKey
            fileListModel.selection = fileListModel.entries.first {
                $0.kind == .folder
                    && $0.url.normalizedPathKey == prevKey
            }?.url
            recordHistory()
        } else if let firstFile = fileListModel.entries.first(where: { $0.kind == .file }) {
            host.switchFile(to: firstFile.url)
            recordHistory()
        } else {
            fileListModel.selection = nil
            recordHistory()
        }
    }

    /// このウィンドウでこれまでにアクティブになった最上位のディレクトリ(rootDirectory)を更新する。
    /// target が rootDirectory の祖先(より上位)なら、そこを新たな最上位として記録する。
    /// 既に到達した最上位より下位・並列のディレクトリへ移動しても rootDirectory は変えない。
    private func updateRootDirectory(with target: URL) {
        let rootComponents = fileListModel.rootDirectory.standardizedFileURL.pathComponents
        let targetComponents = target.pathComponents
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
            refreshFileList()
            // ファイルがディレクトリ外(上へ移動で記録されたエントリ)の場合、
            // ファイルの親フォルダを選択して元の状態を復元する
            let fileDir = host.currentFileURL.deletingLastPathComponent().normalizedPathKey
            if fileDir != fileListModel.currentDirectory.normalizedPathKey {
                fileListModel.selection = fileListModel.entries.first {
                    $0.kind == .folder
                        && $0.url.normalizedPathKey == fileDir
                }?.url
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

    /// 履歴状態をサイドバー（FileListModel）へ反映する。
    private func refreshHistoryState() {
        fileListModel.backHistory = history.backEntries()
        fileListModel.forwardHistory = history.forwardEntries()
    }
}
