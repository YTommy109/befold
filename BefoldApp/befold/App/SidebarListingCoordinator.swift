import Foundation

/// サイドバーのファイル一覧の**取得の発行と着地**(TASK-442.5)。
///
/// 抱える関心は 1 つ——「いま出すべき一覧はどれか」を世代で決めること。列挙の発行、
/// 古い結果の破棄、git 状態との待ち合わせがここに閉じる。行の組み立ては
/// `SidebarTreePresenter`、選択の決定は呼び出し側(`onApplied`)、git の反映可否は
/// `FileListModel.applyGitStatus`(ADR 0003)が持つ。
///
/// 表示設定の変更(`applyDisplayChange`)をここに置いているのは、4 値が列挙の
/// **入力**(隠しファイル・並び順・絞り込み・レイアウト)だから。値ごとに後処理が違う
/// (再列挙する / 展開を捨てる / git を取り直すだけ)ため、入口を 1 本に畳んで
/// 「ライブ値の更新・既定値の書き戻し・後処理」を必ず対で走らせる。
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
    /// アプリ全体の既定値への書き戻し口。**読み取りを持たない**プロトコルなので、
    /// この窓が保存値を読み直す経路はコンパイル時に作れない(ADR 0002「窓の状態の規則」2)。
    private let displayDefaults: any SidebarDisplayDefaultsRecording
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
        displayDefaults: any SidebarDisplayDefaultsRecording,
        tree: SidebarTreePresenter,
        gitStatus: SidebarGitStatusCoordinator,
        baseDirectory: SidebarBaseDirectoryResolver
    ) {
        self.fileListModel = fileListModel
        self.directoryLister = directoryLister
        self.displayDefaults = displayDefaults
        self.tree = tree
        self.gitStatus = gitStatus
        self.baseDirectory = baseDirectory
    }

    /// host を接続する。SidebarNavigator.attach(to:) が中継する。
    func attach(to host: SidebarNavigatorHost) {
        self.host = host
    }

    /// サイドバー表示 4 値を変える**唯一の入口**。この窓のライブ値
    /// (`FileListModel`)を更新し、同時に「次に窓を開くときの既定値」として書き戻す。
    ///
    /// 4 値は窓ごとのライブ値なので他窓へは配らない(ADR 0002「窓の状態」)。
    /// **ライブ値の更新・既定値の書き戻し・後処理をここで対にしている。** 片方だけを行う
    /// 経路を作らないため、`FileListModel` の 4 プロパティへ外から直接代入しないこと
    /// (例外は CLI の `--sort` / `--hidden-files` = その起動限りの上書きで、
    /// 窓の生成時に初期値へ混ぜる形で効かせ、既定値を書き換えない)。
    ///
    /// 後処理が値ごとに違うのが要点。
    /// - 隠しファイル・並び順: 一覧の中身が変わるので再列挙する。
    /// - レイアウト: 行配列そのものが変わる。展開状態はここでは捨てない——ドリルダウンは
    ///   展開の材料を行へ渡さない(SidebarTreePresenter.applyRows)ので表示に出ず、ツリーへ
    ///   戻るときの復元材料として温存する。捨てる判断ごと切り替えの前後処理は
    ///   `SidebarLayoutTransition` が持つ(TASK-481)。行の組み直しは
    ///   `refreshFileList` の経路へ合流させる——直接組み直すと「ルートの一覧が届く前に
    ///   行を組み直さない」不変条件を迂回する。
    /// - 変更ファイルのみ: 述語が変わるだけなので再列挙しない。ON になったときだけ git 状態を
    ///   取り直す(作業ツリーの編集は index も windowDidBecomeKey も動かさないため / TASK-296)。
    ///   OFF は絞り込みをやめるだけで新しい git 状態を要さず、方向を見ずに取り直すと開いている
    ///   ウィンドウ数だけ git status が同時に走る(TASK-303)。
    func applyDisplayChange(_ change: SidebarDisplayChange) {
        switch change {
        case .toggleHiddenFiles:
            fileListModel.showHiddenFiles.toggle()
            recordSettings()
            refreshFileList()
        case .toggleChangedFilesOnly:
            fileListModel.showChangedFilesOnly.toggle()
            recordSettings()
            guard fileListModel.showChangedFilesOnly else { return }
            gitStatus.refresh(policy: .always)
        case .toggleLayoutMode:
            let next: SidebarLayoutMode = fileListModel.layoutMode == .tree ? .drillDown : .tree
            fileListModel.layoutMode = next
            recordSettings()
            refreshFileList()
        case let .setSortOrder(order):
            guard fileListModel.sortOrder != order else { return }
            fileListModel.sortOrder = order
            recordSettings()
            refreshFileList()
        }
    }

    /// この窓の現在値を、次に開く窓の既定値として書き戻す。後勝ちでよい。
    private func recordSettings() {
        displayDefaults.record(fileListModel.displaySettings)
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
        let showHiddenFiles = fileListModel.showHiddenFiles
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
