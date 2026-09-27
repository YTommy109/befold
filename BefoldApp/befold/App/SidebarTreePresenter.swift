import Foundation

/// サイドバーの行を組み立てて `FileListModel` へ反映する型(TASK-442.3)。
///
/// 抱える関心は 1 つ——`FileListModel.entries` という 1 本の出力を作ること。
/// そのための**状態**(`expansion`)・**材料**(`lastListing`)・**取得**(`childrenLister`)・
/// **組み立てと反映**(`applyRows`)をここに閉じる。展開と寿命を共有するスナップショット
/// root の中継(TASK-481)も持つ——`expansion` を `private` に保つための薄い委譲で、
/// 行の組み立てとは別の関心だが置き場は寿命の結合が決める。`SidebarNavigator` から分けているのは
/// 行数ではなく、`lastListing` を `private` にできるようにするため。別ファイルの
/// extension が書く形だと Swift の `private`(ファイルスコープ)では守れず、
/// 「書いてよいのは `applyRows` だけ」が doc コメントの約束にとどまっていた。
///
/// **この型が `fileListModel` へ書く値は `entries` / `entriesDirectory` だけ**
/// (`setEntries` 経由)。選択・カレントディレクトリ・git 状態は `SidebarNavigator` が書く。
/// 属性が重ならないので、同じオブジェクトを 2 つの型が書いても関心は混ざらない。
/// ほかに init で `onGitStatusChange` を繋ぎ(購読者はこの型だけ / TASK-641)、
/// 行の組み立てとレビュー表示の規則のために `display` / `gitStatus` / `currentDirectory` と
/// 反映済みの一覧(`entries` / `entriesDirectory` ほか。同値判定とフォルダー行の引き当て)を読む。
///
/// 生成は `SidebarNavigator.init` の内側だけ。注入引数にすると、渡し忘れが
/// コンパイルエラーにならず静かに別インスタンスになる(TASK-319 と同型)。
///
/// - Note: `reloadExpandedChildren` はルートの列挙を**発行する前**に呼ばれるため、
///   子リストがルートの一覧より先に着地すると、その 1 回だけ古い `lastListing` で
///   行が組み直される。TASK-442.3 時点の既存の窓で、ここでは塞いでいない。
@MainActor
final class SidebarTreePresenter {
    /// 行の反映先。書く値は `entries` / `entriesDirectory` だけ(読み取りと購読の接続は型 doc を参照)。
    private let fileListModel: FileListModel
    /// 展開したフォルダの子リストの取得元。ルートの一覧(`SidebarNavigator.directoryLister`)とは
    /// **別の関数**であることが要点で、あちらは親移動行を別に持つルート一覧の材料を返す。
    /// **nil は列挙失敗**(空のフォルダの `[]` と区別する)。
    private let childrenLister: (URL, SortOrder, Bool) async -> [FileListEntry]?
    /// ツリー展開の状態と、展開したフォルダの子リスト。
    private let expansion = SidebarExpansion()
    /// 直近に `applyRows` へ渡した列挙結果。行を組み直すたびに組み立て済みの配列から
    /// 材料を復元しないために持つ。**書いてよいのは `applyRows` だけ**(他所から書くと、
    /// 世代ガードを通っていない古い列挙で `rebuildRows` が走る)。
    /// **書いてよいのは `applyRows` だけ**なので `private(set)`。読み取りは、この窓の
    /// 列挙結果を新しい窓の出発点として渡す `SidebarListingSeed` の組み立てが使う。
    private(set) var lastListing = DirectoryListing.empty

    /// 展開中フォルダの pathKey。テストが展開状態を検証するための読み取り専用の窓。
    var expandedKeys: Set<String> {
        expansion.expandedKeys
    }

    init(
        fileListModel: FileListModel,
        childrenLister: @escaping (URL, SortOrder, Bool) async -> [FileListEntry]?
    ) {
        self.fileListModel = fileListModel
        self.childrenLister = childrenLister
        fileListModel.onGitStatusChange = { [weak self] in self?.revealChangedFolders() }
    }

    // MARK: - Row Assembly

    /// ルートの列挙結果(材料)と展開の材料から行配列を組み立て、`fileListModel` へ
    /// 反映して**反映した行**を返す。
    ///
    /// `fileListModel.setEntries` を呼ぶのはプロダクトではここ 1 箇所だけ。呼び出し元が
    /// それぞれ畳むと、展開の材料を渡し忘れた経路がドリルダウンのまま残る
    /// (`SidebarRowAssemblySingleSourceTests` がソース走査で数えている)。
    /// 呼び出し元は戻り値を使って選択維持を判定すること(ルート直下だけを見ると、
    /// 展開したサブフォルダ内のファイルを選んでいる間ずっと選択が飛ぶ)。
    ///
    /// `lastListing` と `entriesDirectory` は**この同じ同期区間で**書く。片方だけが
    /// 進む窓があると、`rebuildRows` が別ディレクトリの材料で行を組む。
    ///
    /// **前回と完全に同じ結果なら `setEntries` を呼ばない**(TASK-532)。同じディレクトリを
    /// 取り直す契機はウィンドウ生成直後とキー化のたびにあり、素通しすると
    /// `FileListModel.entryIndex` を毎回作り直す。
    ///
    /// 止めたいのは**索引の作り直しと、それが引き起こす提示対象の無効化**であって、
    /// 「観測対象への同値の代入」ではない。Swift の Observation は Equatable な値の
    /// 同値代入では観測を汚さない(実測: `entries` / `sortOrder` / `filterText` /
    /// `gitStatus` / `baseDirectory` はいずれも発火 0)。一方 `entryIndex` は
    /// Equatable ではないので作り直すたびに必ず汚れ、`previewTarget` を読む側
    /// (ViewerContentView・ツールバー同期)がウィンドウをキーにするたびに再評価される。
    ///
    /// 判定をここに置くのは、`lastListing` の更新と同じ同期区間に収めるため(モデル側へ
    /// 置くと材料だけが進む窓ができる)。`lastListing` は行に出ない差でも更新してよいので、
    /// 上の不変条件は保たれる。
    @discardableResult
    func applyRows(_ listing: DirectoryListing, for directory: URL) -> [FileListEntry] {
        lastListing = listing
        let isTree = fileListModel.display.layoutMode == .tree
        // ドリルダウン表示では展開の材料を渡さない。展開状態が残っていても
        // 行は 1 階層ぶんに戻る(モードを戻したのにツリーのままになるのを防ぐ)。
        let rows = listing.rows(
            material: isTree ? expansion.material : .init(), showsDisclosure: isTree
        )
        // 列挙に失敗したかは行と一緒に渡す。行の有無からは判定できない——失敗しても
        // 親移動行と「いま開いている文書」の行は出るため(TASK-410)。
        //
        // 比較するのは `setEntries` が書く値の全量(3 つ + 一覧の到着を表す
        // `hasLoadedEntries`)。`setEntries` に値を足すときは、ここの比較にも足すこと。
        // 挙げ漏れると「変わったのに描き直されない」へ反転する。git バッジ・絞り込み・
        // フィルターは `entries` に含まれないが、いずれも `listSnapshot` 側の導出で
        // 適用される別の観測値なので、ここで止めても追随する。
        let isUnchanged = fileListModel.hasLoadedEntries
            && fileListModel.entriesDirectory == directory
            && fileListModel.didFailListing == listing.didFailEnumeration
            && fileListModel.entries == rows
        if !isUnchanged {
            fileListModel.setEntries(
                rows, for: directory, didFailEnumeration: listing.didFailEnumeration
            )
        }
        // ルートの一覧が着地した時点 = フォルダー移動・窓を開く・ツリーへの切り替えの
        // 着地点。`reloadExpandedChildren` はこの一覧の発行前に済んでいるので、ここで
        // 始めた展開の券はそれに無効化されない。
        revealChangedFolders()
        return rows
    }

    /// 手元の展開の材料だけで行を組み直す。子リストが届いたときに呼ぶ。
    /// ルートを列挙し直さないので、展開のたびにルートの再列挙は起きない。
    ///
    /// 保持している材料(`lastListing`)をそのまま使う。組み立て済みの
    /// `fileListModel.entries` から `depth == 0` でルート行を復元してはならない
    /// (組み立て → 分解 → 再組み立ての往復に戻る / TASK-442.1)。
    private func rebuildRows() {
        applyRows(lastListing, for: fileListModel.entriesDirectory)
    }

    /// 予約中の組み直し。nil なら予約なし。本体は同期処理だけなので、走り始めた時点で
    /// nil に戻しても、他の誰かが「走り途中」を観測することはない。
    private var pendingRebuild: Task<Void, Never>?

    /// 子リストの着地ごとの組み直しを、同じ時期に届いたぶんで 1 回へまとめる(TASK-637)。
    ///
    /// 組み直しは全行の組み立てで、700 行で 1 回約 12ms(実測)。着地ごとに組み直すと、
    /// レビュー表示で 400 フォルダーを一度に開いたとき 400 回走り、全行が揃うまで約 3.8 秒
    /// かかった。まとめると 80ms(`.tmp` の 400 変更フォルダーのリポジトリで実測)。
    /// 組み直しは次のメインアクター実行へ遅れるが、読むのはその時点の `lastListing` なので
    /// 古い材料で組むことはない。
    private func scheduleRebuild() {
        guard pendingRebuild == nil else { return }
        pendingRebuild = Task {
            self.pendingRebuild = nil
            self.rebuildRows()
        }
    }

    /// 走行中の子リスト取得(フォルダーの pathKey ごとに最新の 1 本)。待ち合わせ専用。
    ///
    /// **走行中の、まだ有効な取得だけを持つ**(TASK-644)。外す経路は 2 つで、どちらも
    /// 券の寿命(`SidebarExpansion` の世代・epoch)に合わせている。
    /// - 着地: `expansion.apply` が受け付けたら自分のエントリを外す。受け付けた券は
    ///   そのキーの最新なので、エントリは必ず自分。
    /// - 無効化: 券を無効にした側が同じ範囲で外す。取り直し(`loadChildren` が上書き・
    ///   `reloadExpandedChildren` が epoch ごと空に)、畳み(`collapseFolder` が
    ///   `collapse` の捨てたキーを外す)、展開の破棄(`invalidateExpansion`)。
    ///
    /// 無効化済みの取得を残すと、ゲートで止めたままの古い取得を `awaitSettled` が待って
    /// ハングし、完了済みの Task は展開中ずっと保持される。
    private var childTasks: [String: Task<Void, Never>] = [:]

    /// 走行中の子リスト取得のキー。`childTasks` の不変条件をテストが測るための読み取り窓。
    var pendingChildKeys: Set<String> {
        Set(childTasks.keys)
    }

    /// 発行済みの子リスト取得と、それが予約する行の組み直しが済むまで待つ。
    /// `SidebarNavigator.awaitSettled()` の一部で、テストの待ち合わせ用(TASK-642)。
    func awaitSettled() async {
        // 組み直しがレビュー表示の規則を通って次の展開を始めることがあるので、
        // どちらも空になるまで回す。
        // 待ち終えた取得は覚えて飛ばすだけで、`childTasks` からは外さない。外すのは
        // 着地と無効化の経路だけで、ここが外すと不変条件の破れを覆い隠す。
        var awaited: Set<Task<Void, Never>> = []
        while true {
            if let task = childTasks.values.first(where: { !awaited.contains($0) }) {
                awaited.insert(task)
                await task.value
            } else if let rebuild = pendingRebuild {
                await rebuild.value
            } else {
                return
            }
        }
    }

    // MARK: - Tree Expansion

    /// フォルダを展開する。既に展開済みなら何もしない(再列挙しない)。
    /// 列挙は `childrenLister`(nonisolated async)が行うため、MainActor 上では列挙しない。
    func expandFolder(_ key: String, at url: URL) {
        guard let token = expansion.beginExpanding(key, at: url) else { return }
        loadChildren(for: token)
    }

    /// フォルダを畳む。配下の展開も一緒に捨てる(SidebarExpansion.collapse を参照)。
    func collapseFolder(_ key: String) {
        for dropped in expansion.collapse(key) {
            childTasks[dropped] = nil
        }
        rebuildRows()
    }

    /// 展開中フォルダの pathKey → URL。別の窓へ引き継ぐための読み取り窓。
    var expandedFolderURLs: [String: URL] {
        expansion.expandedFolderURLs
    }

    /// 別の窓から引き継いだ展開を当てる(TASK-593.2)。
    ///
    /// **行の材料が入った後に呼ぶこと。** `expandFolder` は子リストの着地時に行を
    /// 組み直すので、`lastListing` が空のまま呼ぶと空の一覧に対して組み直す。
    ///
    /// 展開はツリー表示でしか行に効かないので、リスト表示では引き継がない
    /// (引き継ぐと、この窓が一度もツリーにしていないのに展開キーだけ溜まる)。
    func adoptExpansion(_ inherited: [String: URL]) {
        guard fileListModel.display.layoutMode == .tree else { return }
        for (key, url) in inherited {
            expandFolder(key, at: url)
        }
    }

    /// 走行中の子リスト取得をすべて無効化し、展開状態を捨てる(snapshotRoot も一緒に消える)。
    /// ツリー表示中のルート切り替え・ウィンドウを閉じるとき・スナップショット root の外で
    /// ツリー表示へ戻るときに呼ぶ。
    func invalidateExpansion() {
        expansion.invalidateAll()
        childTasks.removeAll()
        lastReveal = nil
    }

    // MARK: - Review Expansion (TASK-637)

    /// レビュー表示(ツリー × 変更のみ)で最後に規則を適用したときの、表示中ディレクトリ・
    /// git 状態・候補。**展開を「入る前へ戻す」ための保存ではない**——全件を開くか差分だけを
    /// 開くかを分け、差分の引き算に前回の候補を使い回すためだけに持つ(TASK-638)。
    /// 組み合わせを外れたら nil。
    ///
    /// 寿命は `expansion` と同じ。前回の候補はそれが開いた展開が残っている間だけ意味を持つので、
    /// `invalidateExpansion` で展開と一緒に捨てる(残すと、同じ git 状態の着地が「適用済み」と
    /// 判定され、捨てた展開が開き直らない。TASK-645)。
    private struct Reveal {
        let directoryKey: String
        let status: SidebarGitStatus
        let targets: Set<String>
    }

    private var lastReveal: Reveal?

    /// レビュー表示の規則: 変更ファイルの祖先フォルダーを展開集合へ**足す**(閉じない)。
    ///
    /// - このディレクトリで未適用(組み合わせに入った・移動した・窓を開いた): 全件を開く。
    /// - 適用済み: 前回の候補に無かったフォルダーだけを開く。利用者が閉じたフォルダーは
    ///   前回の候補にも含まれるので、git 状態が更新されても開き直らない。
    ///
    /// 呼ぶのは一覧の着地(`applyRows`)・git 状態の変化(`FileListModel.onGitStatusChange`)・
    /// 表示設定の変更(`SidebarListingCoordinator.applyDisplayChange`)の 3 箇所。
    func revealChangedFolders() {
        let display = fileListModel.display
        let isReviewDisplay = display.layoutMode == .tree && display.showChangedFilesOnly
        guard isReviewDisplay, let status = fileListModel.gitStatus else {
            lastReveal = nil
            return
        }
        // 適用先は**着地済みの一覧**のディレクトリ。移動中は `currentDirectory` だけが先に
        // 進み、手元の行と git 状態は移動前のもの。そこで開くと移動前の状態で移動先の
        // フォルダーを開いてしまうので、移動先の一覧が着地する `applyRows` まで待つ(TASK-639)。
        let directoryKey = fileListModel.entriesDirectory.normalizedPathKey
        guard directoryKey == fileListModel.currentDirectory.normalizedPathKey else { return }
        let previous = lastReveal?.directoryKey == directoryKey ? lastReveal : nil
        // フォーカス復帰のたびに通る経路。状態が同じなら候補を数えもしない。
        // 同値の取り直しは `FileListModel.setGitStatus` が代入ごと弾くので、ここの比較は
        // 同一ストレージの早期 return で O(1) に終わる(TASK-646)。
        guard previous?.status != status else { return }
        // ponytail: 未追跡エントリごとに stat 1 回(メインアクター)。数千件の未追跡で
        // 重ければ GitStatusReader で畳み込みの事実(末尾スラッシュ)を運ぶ。
        let targets = status.foldersToReveal(under: directoryKey) {
            DirectoryLister.isDirectory(URL(fileURLWithPath: $0, isDirectory: true))
        }
        lastReveal = Reveal(directoryKey: directoryKey, status: status, targets: targets)
        for key in targets.subtracting(previous?.targets ?? []) {
            expandFolder(key, at: URL(fileURLWithPath: key, isDirectory: true))
        }
    }

    // MARK: - Layout Snapshot (TASK-481)

    /// 以下 4 本は `SidebarExpansion` のスナップショット root への薄い委譲。
    /// 呼び出し元はツリー⇄リスト切り替えの遷移(SidebarLayoutTransition)だけ。
    var snapshotRoot: URL? {
        expansion.snapshotRoot
    }

    func recordSnapshotRoot(_ root: URL) {
        expansion.recordSnapshotRoot(root)
    }

    func clearSnapshotRoot() {
        expansion.clearSnapshotRoot()
    }

    func snapshotRootCovers(_ url: URL) -> Bool {
        expansion.snapshotRootCovers(url)
    }

    /// 展開中フォルダの子リストを、現在の並び順・隠しファイル設定で取り直す。
    /// 取り直さないと、展開中のサブツリーだけが古い規則で並び続ける。
    ///
    /// ここで行を組み直してはならない。この関数はルートの列挙を**発行する前**に呼ばれ、
    /// そのルートの一覧はまだ届いていない。組み直すと手元の古い行で `setEntries` が走り、
    /// 一覧の到着前に `hasLoadedEntries` が立って「対象が確定していない」状態が失われる
    /// (previewTarget が .undetermined を返せなくなる)。行はルートの一覧が届いた時点と、
    /// 子リストが届いた時点(loadChildren)で組み直す。
    /// **いまの一覧にフォルダー行が無いキーは取り直さない。** この関数はルートを取り直す
    /// たびに呼ばれるため、Finder 側で消された・改名されたフォルダーを展開したまま残すと、
    /// 以後ウィンドウがキーになるたびに存在しないパスへ列挙が飛ぶ(低速なボリュームでは
    /// タイムアウトまで待たされ、結果は `.failed` なので読み込み済みの子行も毎回捨てられる
    /// / TASK-451)。行が無いキーの子は古いまま残るが、親の行が無いので描画されない。
    func reloadExpandedChildren() {
        // リスト(ドリルダウン)表示中は展開が行に出ない(applyRows が材料を渡さない)。
        // 温存中の子リストを取り直しても描画されず、不可視のサブツリーへ列挙が飛ぶ
        // だけなので何もしない。鮮度はツリーへ戻ったあとの取り直しで追いつく(TASK-481)。
        guard fileListModel.display.layoutMode == .tree else { return }
        let tokens = expansion.invalidateChildren()
        // epoch が進み、走行中の取得はすべて無効になった。取り直すキーは下で入れ直す。
        childTasks.removeAll()
        for token in tokens {
            // 判定に使うのは 1 つ前の完了した一覧(この関数はルートの列挙を発行する前に
            // 呼ばれる)。列挙先の URL は従来どおり券が運ぶ——ここで引き当て直さない。
            // **`.loading` のキーは行が無くても必ず取り直す。** 走行中の初回取得はいま
            // epoch で捨てたので、再発行しなければ答えが永久に届かない。行が無いのは
            // 消えたからとは限らず、親の子リストの着地待ち(入れ子の一括展開)でもある。
            // 飛ばしてよいのは答えを持っている(古い子を出し続けられる)キーだけ(TASK-643)。
            let awaitingFirstAnswer = expansion.children[token.key] == .loading
            guard awaitingFirstAnswer || fileListModel.folderEntryURL(forKey: token.key) != nil else { continue }
            loadChildren(for: token)
        }
    }

    /// 券が指すフォルダの子リストを取り直し、着地したら行を組み直す。
    /// 列挙先の URL は券が運ぶ(一覧から pathKey で引き当て直さない / TASK-442.3)。
    private func loadChildren(for token: SidebarExpansion.ExpansionToken) {
        let sortOrder = fileListModel.display.sortOrder
        let showHiddenFiles = fileListModel.display.showHiddenFiles
        childTasks[token.key] = Task {
            let children = await self.childrenLister(token.url, sortOrder, showHiddenFiles)
            if self.expansion.apply(children, for: token) {
                self.childTasks[token.key] = nil
            }
            self.scheduleRebuild()
        }
    }
}
