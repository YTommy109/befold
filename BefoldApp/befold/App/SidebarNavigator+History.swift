import Foundation

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
