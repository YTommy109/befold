import Foundation

/// 戻る/進む履歴の記録と適用(TASK-442.5)。
///
/// 一覧・git 状態の取得とは独立した関心事で、`NavigationHistory` と
/// `FileListModel` / host の橋渡しだけを担う。
///
/// **この型は `fileListModel` を読むだけで、書かない(TASK-471)。**
/// 戻る/進むの可否と履歴メニューの中身は `history` を読み手が直接見る(TASK-458)。
/// `fileListModel` へ写しを置くと、写し忘れたときにボタンの有効状態だけが古くなる。
/// 履歴適用による表示中フォルダーの移動・選択の確定・一覧の取り直しは、ファイル切替後と
/// 同じ `SidebarPostSwitchSync` の同期区間へ通す(TASK-445 / TASK-465 / TASK-468)。
///
/// `navigator` を weak で持つのは、その同期区間が `SidebarNavigator` の経路
/// (`moveCurrentDirectory(to:)` / `refreshFileList(applyCustomSelection:)`)を
/// 借りて動くため。「サイドバー側の正規経路を借りる」1 つの用途で、履歴が独自に
/// 同じ後始末を書き写さないためのもの。
@MainActor
final class SidebarHistoryController {
    private let fileListModel: FileListModel
    /// このタブの戻る/進むナビゲーション履歴(メモリ内のみ)。
    /// 読み手(ツールバー・メニュー判定)は `SidebarNavigator.navigationHistory` 経由で
    /// これを直接読む。書き換えるのはこの型だけ。
    let history = NavigationHistory()
    private weak var host: SidebarNavigatorHost?
    /// 同期区間(`SidebarPostSwitchSync`)を通すときの経路の借り先。用途はそれ 1 つ。
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

    /// 現在の表示状態(ディレクトリ＋ファイル＋提示対象)を履歴に記録する。
    /// push は現在エントリと同一なら無視する。
    func record() {
        guard let host else { return }
        history.push(HistoryEntry(
            directory: fileListModel.currentDirectory,
            file: host.currentFileURL,
            presentation: currentPresentation(host: host)
        ))
        refreshState()
    }

    /// いま提示している対象を履歴用のスナップショットへ写す。
    ///
    /// `.undetermined`(一覧がまだ届いていない)は **ファイル提示として記録する**。
    /// ウィンドウ生成直後の記録(`ViewerWindowController` の初期化末尾)は必ずここに落ちるが、
    /// そのときウィンドウが出しているのは開いた文書であって一覧ではない。「未確定だから
    /// フォルダー」に倒すと、起動直後のエントリへ戻るたびに一覧が被さる。
    private func currentPresentation(host: SidebarNavigatorHost) -> HistoryPresentation {
        switch fileListModel.previewTarget {
        case .folder:
            .folder(fileListModel.selection)
        case .file:
            .file(fileListModel.selection ?? host.currentFileURL)
        case .undetermined:
            .file(host.currentFileURL)
        }
    }

    /// rename/move を履歴へ反映し、履歴状態を更新する。
    func applyRename(from oldURL: URL, to newURL: URL) {
        history.renameOccurred(from: oldURL, to: newURL)
        refreshState()
    }

    /// 履歴エントリを表示へ適用する。適用できなかった場合は false を返す。
    private func applyEntry(_ entry: HistoryEntry) -> Bool {
        // navigator も先に確かめる。切替を済ませてから欠けに気づくと、ファイルだけが
        // 変わって同期区間を通らない部分適用になる。
        guard let host, let navigator else { return false }
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
        // 表示中フォルダーの移動・選択の確定・一覧の取り直しは、ファイル切替後と同じ
        // 同期区間を通す(TASK-471)。記録した提示対象をそのまま選択として渡すだけで、
        // 「開いている文書の親フォルダー行を引く」といった推論は挟まない(TASK-468)。
        // 一覧は移動の有無によらず取り直す(記録した行が今の一覧に無い場合の上積み)。
        SidebarPostSwitchSync.apply(
            on: navigator,
            movingTo: dirChanged ? entry.directory : nil,
            selecting: entry.presentation.selectionURL,
            refreshesWhenStaying: true
        )
        return true
    }

    /// 履歴状態の変化をホスト(ツールバー)へ知らせる。値は渡さず、読み手が
    /// `history` を読み直す(写しを持たないため取り違えが起きない / TASK-458)。
    private func refreshState() {
        host?.historyStateDidChange()
    }
}
