import Foundation

/// サイドバーのファイル一覧の**取得の発行と着地**(TASK-442.5)。
///
/// 抱える関心は 1 つ——「いま出すべき一覧はどれか」を世代で決めること。列挙の発行、
/// 古い結果の破棄、git 状態との待ち合わせがここに閉じる。行の組み立ては
/// `SidebarTreePresenter`、選択の決定は呼び出し側(`onApplied`)、git の反映可否は
/// `FileListModel.applyGitStatus`(ADR 0003)が持つ。
///
/// 表示設定のミラー同期(`syncDisplayPreferences`)をここに置いているのは、列挙の
/// **入力**(隠しファイル・並び順・絞り込み・レイアウト)だから。列挙のたびに真実の源から
/// 読み直す形にしておかないと、設定変更が次の一覧に乗らない経路ができる。
@MainActor
final class SidebarListingCoordinator {
    private let fileListModel: FileListModel
    /// ファイル一覧の再取得元。既定は DirectoryLister.listingAsync(nonisolated async)だが、
    /// 再読込経路をテストで差し替えられるよう注入可能にする。async のため呼び出し元アクター
    /// (MainActor)を離れて実行され、巨大ディレクトリでもメインスレッドを塞がない。
    ///
    /// 返すのは **行に畳む前の材料**(DirectoryListing)。畳んだ配列を返させると、
    /// 展開を足す側がそれを分解して材料へ戻す往復が要る(TASK-442.1)。
    private let directoryLister: (URL, SortOrder, Bool) async -> DirectoryListing
    /// 不可視ファイル表示設定。全ウィンドウで共有される単一の真実の源を都度参照する。
    private let sidebarDisplayPreference: SidebarDisplayPreference
    private let tree: SidebarTreePresenter
    private let gitStatus: SidebarGitStatusCoordinator
    private let baseDirectory: SidebarBaseDirectoryResolver
    private weak var host: SidebarNavigatorHost?

    /// 発行した一覧取得タスクの世代番号。新しい要求が来たら古い結果の反映を捨てる
    /// (ViewerStore.loadGeneration と同型)。
    private var generation = 0
    /// 直近に発行した一覧取得タスク。テストから完了を待つために公開する
    /// (通常の待ち合わせは `SidebarNavigator.awaitSettled()` が 3 本まとめて行う)。
    ///
    /// 絞り込み ON のときは git 状態の反映もこのタスクの中で起きる(一覧と git を
    /// 同一メインアクター実行で反映するのが不変条件 / TASK-293)。
    private(set) var pendingTask: Task<Void, Never>?

    init(
        fileListModel: FileListModel,
        directoryLister: @escaping (URL, SortOrder, Bool) async -> DirectoryListing,
        sidebarDisplayPreference: SidebarDisplayPreference,
        tree: SidebarTreePresenter,
        gitStatus: SidebarGitStatusCoordinator,
        baseDirectory: SidebarBaseDirectoryResolver
    ) {
        self.fileListModel = fileListModel
        self.directoryLister = directoryLister
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.tree = tree
        self.gitStatus = gitStatus
        self.baseDirectory = baseDirectory
    }

    /// host を接続する。SidebarNavigator.attach(to:) が中継する。
    func attach(to host: SidebarNavigatorHost) {
        self.host = host
    }

    /// fileListModel 側の表示設定ミラーを真実の源(sidebarDisplayPreference)へ同期し、
    /// showHiddenFiles を返す(DirectoryLister 呼び出し前後の重複読み取りを避けるため)。
    @discardableResult
    func syncDisplayPreferences() -> Bool {
        let showHiddenFiles = sidebarDisplayPreference.showHiddenFiles
        fileListModel.showHiddenFiles = showHiddenFiles
        fileListModel.showChangedFilesOnly = sidebarDisplayPreference.showChangedFilesOnly
        fileListModel.layoutMode = sidebarDisplayPreference.layoutMode
        return showHiddenFiles
    }

    /// サイドバーのファイル一覧を現在のディレクトリで取り直し、現在ファイルを選択する。
    /// - Parameter applyCustomSelection: 一覧反映後(fileListModel.entries 更新後)に呼ばれる。
    ///   選択を自前で決めて true を返すと既定の選択保持/フォールバック処理をスキップする。
    ///   false を返すと既定処理にフォールバックする。履歴適用の「上へ移動」後の
    ///   親フォルダ選択復元に使う。
    func refreshFileList(applyCustomSelection: (() -> Bool)? = nil) {
        guard host != nil else { return }
        performListing(of: fileListModel.currentDirectory) { host, directory, listing in
            let entries = self.tree.applyRows(
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
    /// 「基準ディレクトリ更新 → 表示設定同期 → 世代更新 → メイン外で列挙と git 状態取得 →
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
    /// 列挙が終わり次第反映し、git 状態は単発取得と同じ番号のガードで遅れて反映する(TASK-297)。
    /// - Parameters:
    ///   - directory: 列挙対象のディレクトリ。
    ///   - onApplied: 列挙結果が最新世代かつ host が生存しているときにメインアクターで呼ばれる。
    ///     列挙対象のディレクトリを一緒に渡すため、呼び出し元は `fileListModel.currentDirectory`
    ///     の現在値を読み直さずに `FileListModel.setEntries(_:for:)` へそのまま渡せる(TASK-298)。
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
        generation += 1
        let generation = generation
        // 先に git 側のタスクを起こしてから列挙を待つ。どちらも本体は nonisolated async で
        // 走るため、待ち時間は直列にならず遅いほうに揃う。採番は券の内側に閉じている。
        let request = gitStatus.beginListingRequest(for: directory)
        let task = Task {
            let listing = await self.directoryLister(directory, sortOrder, showHiddenFiles)
            let result = couplesGitStatus ? await self.gitStatus.awaitResult(request) : nil
            guard generation == self.generation, let host = self.host else { return }
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
        pendingTask = task
        // 絞り込み ON の反映は上のタスクの中で起きるので、ここでは何もしない
        // (待ちたいテストは pendingTask を待つ)。OFF のときだけ、一覧と
        // 切り離した反映を coordinator に任せる。
        if !couplesGitStatus {
            gitStatus.applyWhenReady(request)
        }
    }

    /// 進行中の一覧取得を破棄する。ウィンドウを閉じるときに呼ぶ。
    /// キャンセルは協調的で、走り出した列挙は完了して結果を返しうるため世代も進める。
    func cancelPending() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
    }
}
