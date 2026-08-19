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
/// **この型は `fileListModel` の `entries` / `entriesDirectory` だけを書く**
/// (`setEntries` 経由)。選択・カレントディレクトリ・git 状態は `SidebarNavigator` が書く。
/// 属性が重ならないので、同じオブジェクトを 2 つの型が書いても関心は混ざらない。
///
/// 生成は `SidebarNavigator.init` の内側だけ。注入引数にすると、渡し忘れが
/// コンパイルエラーにならず静かに別インスタンスになる(TASK-319 と同型)。
///
/// - Note: `reloadExpandedChildren` はルートの列挙を**発行する前**に呼ばれるため、
///   子リストがルートの一覧より先に着地すると、その 1 回だけ古い `lastListing` で
///   行が組み直される。TASK-442.3 時点の既存の窓で、ここでは塞いでいない。
@MainActor
final class SidebarTreePresenter {
    /// 行の反映先。`entries` / `entriesDirectory` 以外は書かない。
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
    private var lastListing = DirectoryListing.empty

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
        let isTree = fileListModel.layoutMode == .tree
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
        guard !isUnchanged else { return rows }
        fileListModel.setEntries(
            rows, for: directory, didFailEnumeration: listing.didFailEnumeration
        )
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

    // MARK: - Tree Expansion

    /// フォルダを展開する。既に展開済みなら何もしない(再列挙しない)。
    /// 列挙は `childrenLister`(nonisolated async)が行うため、MainActor 上では列挙しない。
    func expandFolder(_ key: String, at url: URL) {
        guard let token = expansion.beginExpanding(key, at: url) else { return }
        loadChildren(for: token)
    }

    /// フォルダを畳む。配下の展開も一緒に捨てる(SidebarExpansion.collapse を参照)。
    func collapseFolder(_ key: String) {
        expansion.collapse(key)
        rebuildRows()
    }

    /// 走行中の子リスト取得をすべて無効化し、展開状態を捨てる(snapshotRoot も一緒に消える)。
    /// ツリー表示中のルート切り替え・ウィンドウを閉じるとき・スナップショット root の外で
    /// ツリー表示へ戻るときに呼ぶ。
    func invalidateExpansion() {
        expansion.invalidateAll()
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
        guard fileListModel.layoutMode == .tree else { return }
        for token in expansion.invalidateChildren() {
            // 判定に使うのは 1 つ前の完了した一覧(この関数はルートの列挙を発行する前に
            // 呼ばれる)。列挙先の URL は従来どおり券が運ぶ——ここで引き当て直さない。
            guard fileListModel.folderEntryURL(forKey: token.key) != nil else { continue }
            loadChildren(for: token)
        }
    }

    /// 券が指すフォルダの子リストを取り直し、着地したら行を組み直す。
    /// 列挙先の URL は券が運ぶ(一覧から pathKey で引き当て直さない / TASK-442.3)。
    private func loadChildren(for token: SidebarExpansion.ExpansionToken) {
        let sortOrder = fileListModel.sortOrder
        let showHiddenFiles = fileListModel.showHiddenFiles
        Task {
            let children = await self.childrenLister(token.url, sortOrder, showHiddenFiles)
            self.expansion.apply(children, for: token)
            self.rebuildRows()
        }
    }
}
