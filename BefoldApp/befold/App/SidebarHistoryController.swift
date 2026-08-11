import Foundation

/// 戻る/進む履歴の記録と適用(TASK-442.5)。
///
/// 一覧・git 状態の取得とは独立した関心事で、`NavigationHistory` と
/// `FileListModel` / host の橋渡しだけを担う。
///
/// **この型が書く `fileListModel` の属性は `backHistory` / `forwardHistory` と、
/// 履歴適用時の `currentDirectory` / `selection`。** 後者 2 つは `SidebarNavigator` も
/// 書くが、書く契機は排他(履歴を辿っている間か、それ以外か)。
///
/// `navigator` を weak で持つのは `refreshFileList(applyCustomSelection:)` を
/// 呼び返すためだけ。履歴の適用はディレクトリを跨ぐと一覧の取り直しを伴うので、
/// この 1 本の逆参照は避けられない(2 本以上要るなら分割自体を見送る、というのが
/// TASK-442.5 の着手判断ラインだった)。
@MainActor
final class SidebarHistoryController {
    private let fileListModel: FileListModel
    /// このタブの戻る/進むナビゲーション履歴(メモリ内のみ)。
    private let history = NavigationHistory()
    private weak var host: SidebarNavigatorHost?
    /// 一覧の取り直しを頼む先。上の doc のとおり用途はそれ 1 つ。
    private weak var navigator: SidebarNavigator?

    init(fileListModel: FileListModel) {
        self.fileListModel = fileListModel
    }

    /// host と navigator を接続する。SidebarNavigator.attach(to:) が中継する。
    func attach(to host: SidebarNavigatorHost, navigator: SidebarNavigator) {
        self.host = host
        self.navigator = navigator
    }

    /// サイドバーの戻る/進む・履歴メニューから呼ばれる。offset 負=戻る / 正=進む。
    func navigate(by offset: Int) {
        guard let entry = history.move(by: offset) else { return }
        if !applyEntry(entry) {
            _ = history.move(by: -offset)
        }
        refreshState()
    }

    /// 現在の表示状態(ディレクトリ＋ファイル)を履歴に記録する。
    /// push は現在エントリと同一なら無視する。
    func record() {
        guard let host else { return }
        history.push(HistoryEntry(directory: fileListModel.currentDirectory, file: host.currentFileURL))
        refreshState()
    }

    /// rename/move を履歴へ反映し、履歴状態を更新する。
    func applyRename(from oldURL: URL, to newURL: URL) {
        history.renameOccurred(from: oldURL, to: newURL)
        refreshState()
    }

    /// 履歴エントリを表示へ適用する。適用できなかった場合は false を返す。
    private func applyEntry(_ entry: HistoryEntry) -> Bool {
        guard let host else { return false }
        let dirChanged = entry.directory.normalizedPathKey
            != fileListModel.currentDirectory.normalizedPathKey
        // 存在しないファイルへは切替できず performFileSwitch が .failed を返す。
        // currentDirectory の書き換えより先に切替を試み、失敗時は状態を一切変えずに
        // return して部分適用による不整合(dir だけ変わって file list 未更新)を防ぐ。
        // 別ウィンドウが同じファイルを開いていても自ウィンドウで切り替える(他ウィンドウの
        // 前面化はしない)。利用者はこのウィンドウの履歴を辿っているだけなので奪わない。
        let fileToOpen = entry.file.flatMap {
            $0.normalizedPathKey == host.currentFileURL.normalizedPathKey ? nil : $0
        }
        if let fileToOpen {
            guard case .switched = host.performFileSwitch(to: fileToOpen) else { return false }
        }
        guard dirChanged else {
            fileListModel.selection = fileListModel.matchingEntryURL(for: host.currentFileURL)
            return true
        }
        fileListModel.currentDirectory = entry.directory
        // ファイルがディレクトリ外(上へ移動で記録されたエントリ)の場合、
        // ファイルの親フォルダを選択して元の状態を復元する(一覧反映後に判定する)。
        let fileDir = host.currentFileURL.deletingLastPathComponent().normalizedPathKey
        navigator?.refreshFileList { [weak self] in
            guard let self, fileDir != fileListModel.currentDirectory.normalizedPathKey else { return false }
            fileListModel.selection = fileListModel.folderEntryURL(forKey: fileDir)
            return true
        }
        return true
    }

    /// 履歴状態をサイドバー(FileListModel)とホスト(ツールバー)へ反映する。
    private func refreshState() {
        fileListModel.backHistory = history.backEntries()
        fileListModel.forwardHistory = history.forwardEntries()
        host?.historyStateDidChange()
    }
}
