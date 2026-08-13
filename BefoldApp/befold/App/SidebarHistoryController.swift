import Foundation

/// 戻る/進む履歴の記録と適用(TASK-442.5)。
///
/// 一覧・git 状態の取得とは独立した関心事で、`NavigationHistory` と
/// `FileListModel` / host の橋渡しだけを担う。
///
/// **この型が書く `fileListModel` の属性は `backHistory` / `forwardHistory` と、
/// 履歴適用時の `selection`。** 選択は `SidebarNavigator` も書くが、書く契機は
/// 排他(履歴を辿っている間か、それ以外か)。表示中フォルダーはこの型からは書かず、
/// `SidebarNavigator.moveCurrentDirectory` へ通す(TASK-465 / TASK-468)。
///
/// `navigator` を weak で持つのは、履歴の適用が一覧の取り直し
/// (`refreshFileList(applyCustomSelection:)`)と表示中フォルダーの移動
/// (`moveCurrentDirectory(to:)`)をどちらも `SidebarNavigator` の経路へ通す必要が
/// あるため。どちらも「サイドバー側の正規経路を借りる」1 つの用途で、履歴が
/// 独自に同じ後始末を書き写さないためのもの。
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
        // 表示中フォルダーの書き換えは SidebarNavigator の 1 経路へ通す(TASK-465)。
        // 直接代入していた頃は選択の記憶・rootDirectory の更新・展開の破棄が素通りし、
        // 別ルートの展開行が残ったまま次の一覧に混ざっていた。
        if dirChanged { navigator?.moveCurrentDirectory(to: entry.directory) }
        // **選択はこの同期区間で確定する。** 一覧の着地に委ねると、世代の追い越しや
        // ウィンドウ解放で着地しなかったときに旧選択(フォルダー行)が残り、
        // 一覧が本文に被さったままになる(SidebarNavigator.syncAfterSwitch と同じ理由 / TASK-445)。
        applySelection(of: entry)
        // 着地側でもう一度書くのは、記録した行が今の一覧に無い場合の上積み。
        // 一覧を取り直すと DirectoryLister.appendingOpenFile が開いている文書の行を
        // 補うため、列挙に載らない拡張子のファイルでもそこで選択が行に当たるようになる。
        navigator?.refreshFileList { [weak self] in
            guard let self else { return false }
            applySelection(of: entry)
            return true
        }
        return true
    }

    /// 記録した提示対象を選択へ書き戻す。同期区間と一覧着地の両方から呼ぶ(冪等)。
    ///
    /// 書くのは記録した URL そのものだけで、「開いている文書の親フォルダー行を引く」
    /// といった推論は挟まない。推論に頼っていた頃は、引けなかったときに選択が nil や
    /// 一覧に無い生 URL になり、提示がフォルダー一覧へ落ちていた(TASK-468)。
    private func applySelection(of entry: HistoryEntry) {
        fileListModel.selection = entry.presentation.selectionURL
            .map { fileListModel.matchingEntryURL(for: $0) }
    }

    /// 履歴状態をサイドバー(FileListModel)とホスト(ツールバー)へ反映する。
    private func refreshState() {
        fileListModel.backHistory = history.backEntries()
        fileListModel.forwardHistory = history.forwardEntries()
        host?.historyStateDidChange()
    }
}
