import AppKit
import BefoldKit
import Foundation

/// サイドバーのファイル一覧と選択状態を保持する監視可能モデル。
/// リネームやディレクトリの変化に追従して一覧・選択を更新できるよう、
/// ウィンドウ側(ViewerWindowController)が参照型で保持して書き換える。
@MainActor
@Observable
final class FileListModel {
    var currentDirectory: URL {
        didSet { notifyPresentationTargetChangeIfNeeded() }
    }

    /// このウィンドウでこれまでにアクティブになった最上位のディレクトリ。
    /// パスコピー機能の相対パス基準として使う(SidebarNavigator.navigateToFolder が更新)。
    var rootDirectory: URL
    /// サイドバーの一覧。代入をもって「一覧が届いた」とみなす(hasLoadedEntries)。
    /// 直接代入すると `entriesDirectory` と `didFailListing` は前回のままになる。
    /// 列挙結果を反映するには `setEntries(_:for:didFailEnumeration:)` を使うこと。
    var entries: [FileListEntry] {
        didSet {
            hasLoadedEntries = true
            promotePendingGitStatusIfNeeded()
            entryIndex = FileListEntryIndex(entries: entries)
            notifyPresentationTargetChangeIfNeeded()
        }
    }

    /// `entries` がどのディレクトリを列挙した結果か。`setEntries` の呼び出し元が
    /// 列挙時に確定させた値をそのまま持たせる。
    ///
    /// 絞り込みは `currentDirectory` ではなく **この値** と突き合わせる。移動要求は
    /// currentDirectory を先に進めるので、一覧が届くまでの間 currentDirectory と
    /// 手元の一覧は別のディレクトリを指す。currentDirectory で突き合わせると、その間だけ
    /// 「状態が別ディレクトリのもの」と判定されて絞り込みが外れ、直前のフォルダーの一覧が
    /// 全件表示される(TASK-293)。
    private(set) var entriesDirectory: URL

    /// `entries` を、それを列挙したディレクトリと一緒に反映する。ディレクトリは
    /// 呼び出し元(SidebarNavigator.performListing)が列挙時に確定させたものをそのまま渡す。
    /// `currentDirectory` からの導出に頼ると、「currentDirectory を書き換える全箇所が
    /// 事前に listingGeneration を進めている」という呼び出し元側の不変条件に依存してしまう
    /// (TASK-298)。ここでは列挙した側の値を直接受け取ることで不変条件をローカルに閉じる。
    ///
    /// **ここは渡されたものを無条件に書く。** 「前回と同じ結果なら書かない」判定は
    /// 唯一の呼び出し元である `SidebarTreePresenter.applyRows` が持つ(TASK-532)。
    /// 材料(`lastListing`)の更新と同じ同期区間で判定する必要があるため。
    /// - Parameter didFailEnumeration: 列挙に失敗したか。行の有無とは別に運ぶ(TASK-410)。
    ///   畳んだ行と一緒に渡させることで、`entries` だけ更新して失敗の事実が前回のまま
    ///   残る経路を作らない。材料側の値は `DirectoryListing.didFailEnumeration`。
    func setEntries(_ newEntries: [FileListEntry], for directory: URL, didFailEnumeration: Bool) {
        entriesDirectory = directory
        didFailListing = didFailEnumeration
        entries = newEntries
        // 選択より遅れて届いた一覧に選択行が含まれる形(ツリー復元・選択復元)では、
        // 選択書き込み時のスクロール要求が空振りしている。新しい一覧で再試行させる。
        tableFocuser.retryPendingScroll()
    }

    /// 手元の一覧の列挙に失敗したか。空の一覧が「空だった」のか「読めなかった」のかを
    /// 分ける唯一の判断材料で、空状態の文言がこれを見る(TASK-410)。
    /// 更新経路は `setEntries` の 1 本に閉じる。
    private(set) var didFailListing = false

    /// `entries` を選択から引くための索引。一覧の代入と同時に作り直す。
    /// 提示対象の導出はこれを介して O(1) で行う(FileListEntryIndex)。
    ///
    /// 観測対象から外してはならない。previewTarget は導出値であり、View が
    /// それを読んだときに依存として登録されるのはここで触れた保存値だけなので、
    /// 外すと「一覧が変わって提示対象も変わったのに再描画されない」が起きる。
    private var entryIndex: FileListEntryIndex

    /// 正規化パスキーから行を引く。引き当ての規則そのものは `FileListEntryIndex` が持ち、
    /// ここは索引(private)への委譲だけを行う。索引を直接公開しないのは、観測依存の
    /// 登録点を「モデルのメソッドを呼ぶ」1 通りに揃えておくため。
    func entry(forPathKey key: String) -> FileListEntry? {
        entryIndex.entry(forPathKey: key)
    }

    /// キーが一致する最初のフォルダー行の URL(`FileListEntryIndex` へ委譲)。
    func folderEntryURL(forKey key: String) -> URL? {
        entryIndex.folderEntryURL(forKey: key)
    }

    /// URL の正規化キーが一致する行の URL。無ければ元の URL(`FileListEntryIndex` へ委譲)。
    func matchingEntryURL(for url: URL) -> URL {
        entryIndex.matchingEntryURL(for: url)
    }

    /// 切替先が「いま出ている一覧から選べる」か。ここが真なら表示中フォルダーは動かさない。
    ///
    /// 判定をサイドバーのレイアウト(tree / drillDown)で分けてはならない。tree では展開した
    /// サブフォルダーの子行も同じ一覧に並ぶため、「親ディレクトリ == currentDirectory」で
    /// 判定すると子ファイルを選ぶたびにフォルダー移動が誤発火する(TASK-465)。
    /// 一覧がまだ届いていない起動直後のために、親ディレクトリの一致も同じ扱いにする
    /// (行が無いだけで、そこは既に表示中のフォルダーであり動かす必要がない)。
    func isReachableInCurrentListing(_ url: URL) -> Bool {
        if url.deletingLastPathComponent().normalizedPathKey
            == currentDirectory.normalizedPathKey { return true }
        return entry(forPathKey: url.normalizedPathKey) != nil
    }

    /// 一覧が一度でも反映されたか。ウィンドウは一覧を空で作って非同期に埋めるため、
    /// それまでは「選択が一覧に無い」が「対象が確定していない」を意味する。
    /// 「選択を消してフォルダーを表示している」状態と取り違えないための区別に使う。
    private(set) var hasLoadedEntries: Bool = false

    /// プレビュー領域が提示すべき対象。ViewerContentView と ViewerWindowController が
    /// 同じ値を見るための単一の導出点(ADR 0002)。
    ///
    /// 読み出し側は menu validation(1 回のメニュー表示で 7 セレクタぶん)・ツールバー同期・
    /// View の body 評価と多いが、索引(entryIndex)と選択の pathKey を持っているので
    /// 1 回の導出は O(1) で済む。結果を持たずそのつど導くため、状態が増えず、
    /// ディスク側の変化で持ち回った値が古くなることもない(TASK-273 / TASK-278)。
    var previewTarget: PreviewTarget {
        PreviewTargetResolver.resolve(
            selection: storedSelection,
            selectionPathKey: storedSelectionPathKey,
            entryIndex: entryIndex,
            currentDirectory: currentDirectory,
            hasLoadedEntries: hasLoadedEntries,
            isListingCurrent: entriesDirectory.normalizedPathKey == currentDirectory.normalizedPathKey
        )
    }

    /// 選択中の行の ID(= URL)。Finder/CLI から開いたファイルの URL や
    /// restoreSelection のように、一覧を経由しない生の URL が入ってくる経路があるため、
    /// 書き込み時に native 裏打ちへ揃える。PreviewTargetResolver は body 評価のたびに
    /// `entries.first { $0.id == selection }` を走らせ、片側が NSString 裏打ちだと
    /// 比較のたびに Unicode 正規化が走る(344 件の実測で 1.93ms → 0.035ms)。
    var selection: FileListEntry.ID? {
        get { storedSelection }
        set {
            let normalized = newValue?.nativeBackedFileURL
            // 正規化キーは書き込み時に採る。一覧側(FileListEntry.pathKey)も構築時の
            // スナップショットであり、導出のたびに片側だけディスクを読み直すと、
            // 同じ入力から違う答えが出る(TASK-278)。
            storedSelectionPathKey = normalized?.normalizedPathKey
            storedSelection = normalized
        }
    }

    private var storedSelection: FileListEntry.ID? {
        didSet {
            notifyPresentationTargetChangeIfNeeded()
            scrollSelectionIntoView()
        }
    }

    /// `storedSelection` の `normalizedPathKey`。選択の書き込みと同時に更新する。
    @ObservationIgnored private var storedSelectionPathKey: String?

    /// 提示対象(previewTarget)が変わったときに呼ばれる。
    /// ツールバーの view ベースアイテムは AppKit の validate を通らず、明示的に
    /// 再同期しないと古い有効状態のまま残るため、その通知点として使う(ADR 0002)。
    @ObservationIgnored var onPresentationTargetChange: (() -> Void)?

    /// 直前に通知した提示対象。通知を「変化したときだけ」に絞るための比較用であり、
    /// 提示対象の真実の源ではない(真実の源は previewTarget の導出そのもの)。
    @ObservationIgnored private var lastNotifiedTarget: PreviewTarget

    /// 提示対象が変わりうる書き換えのあとに呼ぶ。実際に変わったときだけ通知する。
    /// currentDirectory / entries / storedSelection の 3 つとも同じここを通す。
    /// フォルダー移動は 3 つを続けて書き換えるため、素通しで通知すると
    /// ツールバーの再同期が 1 回の移動で何度も走る(TASK-278)。
    private func notifyPresentationTargetChangeIfNeeded() {
        let target = previewTarget
        guard target != lastNotifiedTarget else { return }
        lastNotifiedTarget = target
        onPresentationTargetChange?()
    }

    // MARK: - サイドバー表示設定(窓ごとのライブ値)

    //
    // 次の 4 値は ADR 0002「窓の状態」にあたる。**この窓での真実の源はここ**で、
    // アプリ全体の保存値(`SidebarDisplayDefaults`)は窓の生成時に読む初期値にすぎない。
    // 生きている窓は保存値を読み直さない(読み直すと他窓の操作が後から効く)。
    // 変更の入口は `SidebarListingCoordinator.applyDisplayChange(_:)` の 1 本だけで、
    // ここへ外から直接代入しないこと(ライブ値の更新と既定値の書き戻しが対で走らなくなる)。

    /// 一覧の並び順(フォルダー優先 / アルファベット順)。
    var sortOrder: SortOrder
    /// 不可視ファイル(ドットファイル)を一覧に出すか。
    /// サイドバーのアイコンボタン・メニュー・ショートカットの見た目もこの値を読む。
    var showHiddenFiles: Bool
    /// git 変更のあるエントリだけに絞るか。
    var showChangedFilesOnly: Bool
    /// 行の並べ方(ドリルダウン / ツリー展開)。
    /// View はキー操作の割り当てをこの値で切り替える。
    var layoutMode: SidebarLayoutMode
    /// 絞り込みとスライドモード(窓ごと・永続化しない)。保存値の対がある表示 4 値とは
    /// 分けてある。詳しくは `SidebarTransientState` の doc を参照。
    let transient = SidebarTransientState()

    /// 相対パスコピー・Quick Open の基準ディレクトリ。ヘッダーのインジケータ表示に使う。
    /// git ルートの解決は subprocess を伴うため View の body では行わず、
    /// SidebarNavigator が一覧更新と同じ契機でメイン外から解決して書き込む。
    /// 解決前(初回表示直後)は nil でインジケータを出さない。
    var baseDirectory: BaseDirectoryDescriptor?
    /// 「変更のあるファイルのみ」を出してよいか。**メニューもヘッダーもこの値だけを見る。**
    ///
    /// 絞り込む git 状態が無いフォルダーでは、押せても何も起きない(TASK-537)。判定の実体は
    /// `BaseDirectoryDescriptor.allowsGitFeatures(_:)` にあり、差分表示側
    /// (`GitDiffAvailability`)も同じものを見るので、両者の条件がずれない。
    var canFilterChangedFiles: Bool {
        BaseDirectoryDescriptor.allowsGitFeatures(baseDirectory)
    }

    /// 「相対パスをコピー」で書き込む文字列。**規則の実装はここ 1 箇所だけ**にする
    /// (サイドバーと本文のパス参照メニューが同じ項目を持つため。TASK-422)。
    func relativePathForCopy(_ url: URL) -> String {
        PathRelativizer.relativePath(of: url, relativeTo: baseDirectory?.url ?? rootDirectory)
    }

    /// 表示中ディレクトリの git 状態。バッジも「変更のみ表示」の絞り込みもここだけを見る。
    ///
    /// nil は「リポジトリを解決できていない」= git 管理外・取得失敗・機能無効・まだ届いて
    /// いない、のいずれか。**空の値と nil を区別すること**が要点で、変更が 1 つも無い
    /// リポジトリは「空の SidebarGitStatus」であって nil ではない(TASK-285)。
    /// 取得は subprocess を伴うため SidebarNavigator が一覧更新と同じ契機でメイン外から行う。
    /// 書き込みは applyGitStatus(_:for:sequence:) だけを通す。
    private(set) var gitStatus: SidebarGitStatus?

    /// 反映の可否(発行順序 + ディレクトリ対付け)の判定だけを持つ調停器(ADR 0003)。
    ///
    /// **観測対象にしない。** 保留・発行順序の書き換えは画面に出ないため、観測させると
    /// 「保留しただけ」でも再描画とツールバー再同期が走る(TASK-278 と同型)。
    /// 画面に出る値は `gitStatus` だけで、そちらは観測対象のまま残す。
    @ObservationIgnored private var gitStatusGate = FileListGitStatusGate()

    /// `directory` の git 状態を反映する。可否の判定は `FileListGitStatusGate` が一括で行い、
    /// ここは結論を観測対象へ書くだけ。呼び出し元(SidebarNavigator)は sequence の採番だけを
    /// 担い、反映可否の判定には関与しない。
    ///
    /// - Returns: 受け付けた(反映または保留した)なら true。古い発行順序として無視したなら false。
    ///   呼び出し元はこれを見て `.git/index` 監視の張り直し可否を決める。
    @discardableResult
    func applyGitStatus(_ status: SidebarGitStatus?, for directory: URL, sequence: Int) -> Bool {
        let decision = gitStatusGate.accept(
            status,
            forDirectoryKey: directory.normalizedPathKey,
            sequence: sequence,
            entriesDirectoryKey: entriesDirectory.normalizedPathKey
        )
        switch decision {
        case .ignored: return false
        case .deferred: return true
        case let .apply(applied):
            setGitStatus(applied)
            return true
        }
    }

    /// git 状態を観測対象へ書く唯一の実装。**変わったときだけ書く**(TASK-532)。
    /// キー化のたびの取り直しは同じ結果を返すのが普通で、素通しで代入するとバッジが
    /// 変わっていなくてもサイドバーの再評価が走る。`SidebarGitStatus` は Equatable。
    private func setGitStatus(_ newStatus: SidebarGitStatus?) {
        gitStatus = newStatus
    }

    /// `sequence` 以前に発行されたすべての取得結果を無効化する。ウィンドウを閉じるときに呼ぶ
    /// (TASK-300)。
    func invalidatePendingGitStatus(upTo sequence: Int) {
        gitStatusGate.invalidate(upTo: sequence)
    }

    /// 一覧が入れ替わったら、その一覧のディレクトリに対する保留があれば同時に反映する。
    /// entries の代入と同じ実行で書くため、View からは 1 回の更新として見える。
    private func promotePendingGitStatusIfNeeded() {
        if case let .apply(promoted) = gitStatusGate.promote(
            entriesDirectoryKey: entriesDirectory.normalizedPathKey
        ) {
            gitStatus = promoted
        }
    }

    /// サイドバーの NSTableView への操作(フォーカス要求・スクロール追従)。
    /// 参照の設定は SidebarTableViewLocator が行描画時に行う(SidebarTableFocuser)。
    @ObservationIgnored let tableFocuser = SidebarTableFocuser()

    /// 選択行を可視領域へ入れる。選択の書き込み点(storedSelection.didSet)だけを通すので、
    /// 矢印キー・クリック・フィルター・フォルダー再訪時の選択復元が同じ経路で追従する。
    ///
    /// 矢印キーは FileListView.handleKey が `.handled` で受け切っており、裏の NSTableView に
    /// 届かないため AppKit 標準の自動スクロール(選択移動に伴う scrollRowToVisible)は走らない。
    /// SwiftUI の List も、選択バインディングが外から書き換わっただけではスクロールしない(#414)。
    ///
    /// 行番号は `FileListSnapshot.index(of:)` で採る。キー操作側の移動判定と同じ関数を通すので、
    /// 「選択が隠れている」ときの扱いが 2 箇所に分かれない。
    private func scrollSelectionIntoView() {
        tableFocuser.scrollIntoView { [weak self] in
            guard let self, let selection = storedSelection else { return nil }
            return listSnapshot.index(of: selection)
        }
    }

    #if DEBUG
        /// `listSnapshot` の評価回数(テスト計測用の足場)。計数そのものは
        /// `SnapshotEvaluationCounter` が持つ。観測対象にすると読み出しが再描画を
        /// 呼ぶため `@ObservationIgnored`。
        @ObservationIgnored let snapshotEvaluations = SnapshotEvaluationCounter()
    #endif

    /// `directory` のフォルダー一覧(FolderListingView)へ渡す供給元。
    /// 判断の規則は `FolderListingSourceResolver` が持ち、ここは材料を渡すだけ。
    func listingSource(for directory: URL) -> FolderListingSource {
        FolderListingSourceResolver.resolve(
            for: directory,
            in: FolderListingSourceResolver.Listing(
                currentDirectory: currentDirectory,
                entriesDirectory: entriesDirectory,
                hasLoadedEntries: hasLoadedEntries,
                showChangedFilesOnly: showChangedFilesOnly,
                didFailListing: didFailListing
            ),
            filteredRows: { listSnapshot.filtered }
        )
    }

    /// いまの表示設定をまとめた絞り込み。プレビューのフォルダー一覧
    /// (FolderListingView)も同じ値を受け取り、同じ関数で適用する。表示設定は
    /// ここ 1 箇所に集約し、増えたときに片側だけ取り残されないようにする(TASK-288)。
    var listFilter: FileListFilter {
        FileListFilter(
            filterText: transient.filterText,
            gitStatus: showChangedFilesOnly ? gitStatus : nil,
            presentedPathKey: storedSelectionPathKey
        )
    }

    /// - Parameter display: この窓のサイドバー表示 4 値の初期値。本番のウィンドウ生成経路
    ///   (`SidebarNavigator.init`)は `SidebarDisplayDefaults.settings` を流し込む。
    init(
        currentDirectory: URL, entries: [FileListEntry], selection: FileListEntry.ID?,
        display: SidebarDisplaySettings = .initial
    ) {
        self.currentDirectory = currentDirectory
        rootDirectory = currentDirectory
        entriesDirectory = currentDirectory
        self.entries = entries
        let normalizedSelection = selection?.nativeBackedFileURL
        storedSelection = normalizedSelection
        storedSelectionPathKey = normalizedSelection?.normalizedPathKey
        sortOrder = display.sortOrder
        showHiddenFiles = display.showHiddenFiles
        showChangedFilesOnly = display.showChangedFilesOnly
        layoutMode = display.layoutMode
        // 各プロパティの didSet は init 中には走らないため、派生する値をここで揃える。
        entryIndex = FileListEntryIndex(entries: entries)
        lastNotifiedTarget = .undetermined
        lastNotifiedTarget = previewTarget
    }
}
