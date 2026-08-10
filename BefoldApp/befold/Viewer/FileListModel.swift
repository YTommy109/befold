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
    /// 直接代入すると `entriesDirectory` は前回のままになる。列挙したディレクトリと
    /// 一緒に反映するには `setEntries(_:for:)` を使うこと。
    var entries: [FileListEntry] {
        didSet {
            hasLoadedEntries = true
            promotePendingGitStatusIfNeeded()
            entryIndex = FileListEntryIndex(entries: entries)
            notifyPresentationTargetChangeIfNeeded()
        }
    }

    /// `entries` がどのディレクトリを列挙した結果か。`setEntries(_:for:)` の呼び出し元が
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
    func setEntries(_ newEntries: [FileListEntry], for directory: URL) {
        entriesDirectory = directory
        entries = newEntries
    }

    /// `entries` を選択から引くための索引。一覧の代入と同時に作り直す。
    /// 提示対象の導出はこれを介して O(1) で行う(FileListEntryIndex)。
    ///
    /// 観測対象から外してはならない。previewTarget は導出値であり、View が
    /// それを読んだときに依存として登録されるのはここで触れた保存値だけなので、
    /// 外すと「一覧が変わって提示対象も変わったのに再描画されない」が起きる。
    private var entryIndex: FileListEntryIndex

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
            hasLoadedEntries: hasLoadedEntries
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

    var sortOrder: SortOrder
    /// サイドバーのアイコンボタン・メニュー・ショートカットの見た目に使う現在値。
    /// 永続化・真実の源は SidebarDisplayPreference。SidebarNavigator が
    /// refreshFileList()/navigateToFolder(_:) のたびに同期する。
    var showHiddenFiles: Bool = false
    /// git 変更のあるエントリだけに絞るか。永続化・真実の源は SidebarDisplayPreference で、
    /// showHiddenFiles と同じ契機で SidebarNavigator が同期する。
    var showChangedFilesOnly: Bool = false
    /// 行の並べ方(ドリルダウン / ツリー展開)。永続化・真実の源は SidebarDisplayPreference で、
    /// showHiddenFiles と同じ契機で SidebarNavigator が同期する。
    /// View はキー操作の割り当てをこの値で切り替える。
    var layoutMode: SidebarLayoutMode = .drillDown
    /// ファイル名フィルターの検索文字列。フォルダ移動をまたいで保持し、
    /// アプリ再起動時は初期値(空文字列)に戻る(永続化しない)。
    var filterText: String = ""
    /// フィルターフィールドの開閉状態。true の間は navigationHeader 直下に検索欄を表示する。
    var isFilterActive: Bool = false
    /// 相対パスコピー・Quick Open の基準ディレクトリ。ヘッダーのインジケータ表示に使う。
    /// git ルートの解決は subprocess を伴うため View の body では行わず、
    /// SidebarNavigator が一覧更新と同じ契機でメイン外から解決して書き込む。
    /// 解決前(初回表示直後)は nil でインジケータを出さない。
    var baseDirectory: BaseDirectoryDescriptor?
    /// 表示中ディレクトリの git 状態。バッジも「変更のみ表示」の絞り込みもここだけを見る。
    ///
    /// nil は「リポジトリを解決できていない」= git 管理外・取得失敗・機能無効・まだ届いて
    /// いない、のいずれか。**空の値と nil を区別すること**が要点で、変更が 1 つも無い
    /// リポジトリは「空の SidebarGitStatus」であって nil ではない(TASK-285)。
    /// 取得は subprocess を伴うため SidebarNavigator が一覧更新と同じ契機でメイン外から行う。
    /// 書き込みは applyGitStatus(_:for:) だけを通す。
    private(set) var gitStatus: SidebarGitStatus?

    /// まだ手元に一覧が無いディレクトリの git 状態。届いた順に入れてしまうと、画面に出ている
    /// 一覧に対応する状態が失われて絞り込みが一瞬外れるため、一覧が届くまでここで待たせる。
    @ObservationIgnored private var pendingGitStatus: PendingGitStatus?

    /// 直近に**反映を受け付けた** git 状態の発行順序(sequence)。反映の可否はこれとの比較で
    /// 決める(ADR 0003)。「最新の発行と一致」で判定すると、一覧と対で取った結果を捨てないために
    /// sequence を強制的に進める必要が生じ、後から始まった取得の新しい結果を古いスナップショットで
    /// 上書きしてしまう。「これより新しい sequence なら受け付ける」なら、結合取得も後発の単発取得も
    /// どちらも「最後に発行された取得が勝つ」不変条件のまま扱える。sequence の採番元は
    /// SidebarNavigator の gitStatusGeneration。
    @ObservationIgnored private var appliedGitStatusSequence = 0

    /// 保留中の git 状態。**状態が nil(git 管理外・取得失敗)でも「どのディレクトリの結論か」を
    /// 持たせる**のが要点で、これが無いと非 git フォルダーへ移動したときに
    /// 「まだ届いていない」と区別できない。
    private struct PendingGitStatus {
        let directoryKey: String
        let status: SidebarGitStatus?
    }

    /// `directory` の git 状態を反映する。発行順序(recency)とディレクトリ対付けの両方をここで
    /// 一括判定する(ADR 0003)。呼び出し元(SidebarNavigator)は sequence の採番だけを担い、
    /// 反映可否の判定には関与しない。
    ///
    /// recency: `sequence` が直近に受け付けた発行順序より新しくなければ、既に新しい結果が
    /// 反映済み(または反映待ち)であり、この結果は古いので無視する。
    ///
    /// ディレクトリ対付け: 手元の一覧がまだ別のディレクトリのものなら、その一覧が届くまで保留する。
    /// 移動先の状態を先に入れると、画面に出ている一覧(移動元)と突き合わせられなくなって絞り込みが
    /// 外れ、全件が一瞬表示される。実測では `.git/index` 監視や再読込を契機とする単独の
    /// 取得が、移動先を対象に一覧より先に着地していた(TASK-293)。
    ///
    /// - Returns: 受け付けた(反映または保留した)なら true。古い発行順序として無視したなら false。
    ///   呼び出し元はこれを見て `.git/index` 監視の張り直し可否を決める。
    @discardableResult
    func applyGitStatus(_ status: SidebarGitStatus?, for directory: URL, sequence: Int) -> Bool {
        guard sequence > appliedGitStatusSequence else { return false }
        appliedGitStatusSequence = sequence
        let key = directory.normalizedPathKey
        guard key == entriesDirectory.normalizedPathKey else {
            pendingGitStatus = PendingGitStatus(directoryKey: key, status: status)
            return true
        }
        pendingGitStatus = nil
        gitStatus = status
        return true
    }

    /// `sequence` 以前に発行されたすべての取得結果を無効化する。ウィンドウを閉じるときに呼ぶ
    /// (TASK-300)。キャンセルは協調的で、走り出した subprocess は完了して結果を返しうる。
    /// 反映済み sequence を発行済みの先頭へ揃えておかないと、その結果が反映ガードを通り抜け、
    /// 閉じたウィンドウのために `.git/index` 監視を張り直してしまう。
    func invalidatePendingGitStatus(upTo sequence: Int) {
        appliedGitStatusSequence = max(appliedGitStatusSequence, sequence)
    }

    /// 一覧が入れ替わったら、その一覧のディレクトリに対する保留があれば同時に反映する。
    /// entries の代入と同じ実行で書くため、View からは 1 回の更新として見える。
    private func promotePendingGitStatusIfNeeded() {
        guard let pending = pendingGitStatus,
              pending.directoryKey == entriesDirectory.normalizedPathKey
        else { return }
        pendingGitStatus = nil
        gitStatus = pending.status
    }

    /// サイドバー行から見つかった NSTableView への弱参照。SidebarTableViewLocator が
    /// 行描画時に設定する。クリック時に first responder へ昇格させるためだけの
    /// UI 専用値であり、監視対象にする必要はない(#144)。
    @ObservationIgnored
    weak var sidebarTableView: NSTableView?

    /// サイドバーの NSTableView を first responder にする。選択ハイライトを青にし(#144)、
    /// サイドバーを開いた直後からフォルダー名がアクティブ(黒)表示になり矢印キーで操作できるようにする(task-118)。
    /// 参照(sidebarTableView)がまだ解決していない場合は、次のランループで数回だけ再試行する。
    /// サイドバーを畳んだ状態から初めて開いた直後は、List の行(と NSTableView 参照)の生成が
    /// フォーカス要求に間に合わないことがあるため。
    func focusSidebarTable(retriesRemaining: Int = 5) {
        guard let tableView = sidebarTableView, let window = tableView.window else {
            guard retriesRemaining > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.focusSidebarTable(retriesRemaining: retriesRemaining - 1)
            }
            return
        }
        window.makeFirstResponder(tableView)
    }

    /// 選択行を可視領域へ入れる。選択の書き込み点(storedSelection.didSet)だけを通すので、
    /// 矢印キー・クリック・フィルター・フォルダー再訪時の選択復元が同じ経路で追従する。
    ///
    /// 矢印キーは FileListView.handleKey が `.handled` で受け切っており、裏の NSTableView に
    /// 届かないため AppKit 標準の自動スクロール(選択移動に伴う scrollRowToVisible)は走らない。
    /// SwiftUI の List も、選択バインディングが外から書き換わっただけではスクロールしない(#414)。
    ///
    /// 一覧の差し替えより先に選択を書く経路(選択復元)があるため、NSTableView が新しい行を
    /// 反映したあとになるよう次のランループへ遅らせる(固定待ちは不要)。
    private func scrollSelectionIntoView() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let row = selectedRow() else { return }
            sidebarTableView?.scrollRowToVisible(row)
        }
    }

    /// 選択中のエントリが `visibleEntries` の何番目か。List は visibleEntries を 1 セクションで
    /// そのまま描くため、この添字が NSTableView の行番号と一致する。
    private func selectedRow() -> Int? {
        guard let selection = storedSelection else { return nil }
        return visibleEntries.firstIndex { $0.id == selection }
    }

    /// フィルター適用後にサイドバーへ表示するエントリ。`entries`(ディスク由来の一覧)は
    /// 保持したまま、この算出側だけで絞り込む。`.parentNavigation` はフィルター文字列に
    /// 関わらず常に含める(上位フォルダへの移動手段を残すため)。
    /// git 変更での絞り込み(showChangedFilesOnly)も AND で併用する。
    var visibleEntries: [FileListEntry] {
        // 順序が意味を持つ。祖先を足し戻してから開閉三角を確定させること。
        // 逆にすると、「名前は一致するが子が全部消えたフォルダ」の判定が、あとから
        // 足し戻した祖先を子として数えてしまう余地が残る。
        SidebarDisclosureResolver.resolving(
            SidebarTreeFilter.keepingAncestors(of: filteredEntries, in: entries)
        )
    }

    /// 絞り込みだけを適用した一覧(祖先の足し戻し・開閉三角の確定を含まない)。
    ///
    /// プレビューのフォルダー一覧へはこちらを渡す。祖先を足し戻した配列を渡すと、
    /// 「条件に一致しないフォルダ」がプレビューにも現れる一方、同じフォルダを
    /// 自前列挙する経路では消えるため、1 ウィンドウ内に絞り込みの答えが 2 つ並ぶ
    /// (サイドバーとプレビューで答えを 1 つにする TASK-288 の巻き戻し)。
    private var filteredEntries: [FileListEntry] {
        listFilter.apply(to: entries, in: entriesDirectory)
    }

    /// フォルダーを降りた直後に選ぶ行の URL。一覧が空(または `..` しかない)なら nil。
    ///
    /// `.parentNavigation` は上位フォルダーへの移動手段であって一覧の項目ではないため飛ばす。
    /// 選んでしまうと、そのまま Enter や → を押した利用者が今降りてきたばかりの階層へ
    /// 押し戻される。絞り込みは移動をまたいで残るので、`entries` ではなく実際に見えている
    /// 行から採る。ただし**一致した行を優先し、祖先として足し戻されただけの行
    /// (`SidebarTreeFilter`)は飛ばす**(TASK-406)。ツリー表示では一致行の祖先フォルダが
    /// 自分は一致しないまま残るので、見えている先頭をそのまま採ると絞り込みの答えでない行が
    /// 初期選択になり、探していた行まで矢印キーで降りることになる。一致行が 1 つも無い場合
    /// (祖先保持の性質上、通常は起こらない)だけ従来どおり先頭を採る(無選択へは落とさない)。
    var firstSelectableEntryURL: FileListEntry.ID? {
        let selectable = visibleEntries.filter { $0.kind != .parentNavigation }
        let matched = Set(filteredEntries.map(\.id))
        let entry = selectable.first { matched.contains($0.id) } ?? selectable.first
        return entry?.url
    }

    /// `directory` のフォルダー一覧(FolderListingView)へ渡す供給元。
    ///
    /// 表示中ディレクトリを見ているときは、サイドバーが git 状態と一緒に揃えた一覧を
    /// そのまま使わせる。プレビューが自前で列挙すると完了順が揃わず、絞り込みが効く前の
    /// 全件が一瞬描画される(TASK-293)。選択中のサブフォルダーを見ているときは手元に
    /// その一覧が無いので自前で列挙させる(そちらは git 状態の対象外で絞り込み自体が働かない)。
    ///
    /// 表示中ディレクトリの一覧がまだ届いていない間(移動要求で currentDirectory だけが
    /// 先に進んでいる間)の扱いは、**git 絞り込みが ON かどうか**で分かれる。
    ///
    /// - ON: `.shared(nil)` を返して待たせる。自前で列挙させると git 状態と対になっていない
    ///   全件が一瞬描画される(TASK-293 の回帰)。
    /// - OFF: `.ownListing` を返してその場で列挙させる。対にすべき git 状態が無いので待つ
    ///   理由がなく、待たせると移動直後にプレビューが空へ落ちる(TASK-295)。
    ///
    /// ビュー側で「古い自前列挙を出し続ける」形にすると、待つべき場面でも全件が出てしまい、
    /// 列挙し直さないため削除済みのファイルも残る(TASK-301)。判断材料をここに置く。
    func listingSource(for directory: URL) -> FolderListingSource {
        let key = directory.normalizedPathKey
        guard key == currentDirectory.normalizedPathKey else { return .ownListing }
        guard hasLoadedEntries, key == entriesDirectory.normalizedPathKey else {
            return showChangedFilesOnly ? .shared(nil) : .ownListing
        }
        // 絞り込み済みの一覧を渡す。FolderListingView 側はこれを再度 filter.apply に
        // 通さない(FolderListingView.visibleEntries を参照。TASK-298)。
        //
        // **depth 0 の行だけを渡す**。プレビューが見せるのは `directory` 直下であって、
        // サイドバーで展開したその配下ではない。ツリー展開が入ると visibleEntries には
        // 孫以降の行が混ざるため(TASK-361.1)、そのまま渡すと「このフォルダーの中身」
        // として別階層のファイルが並ぶ。ドリルダウンでは全行 depth 0 なので素通し。
        //
        // 祖先を足し戻す**前**の配列(filteredEntries)から採る。足し戻した配列を渡すと、
        // 条件に一致しないフォルダがプレビューにも現れる一方、同じフォルダを自前列挙する
        // 経路では消えるため、1 ウィンドウ内に絞り込みの答えが 2 つ並ぶ(TASK-288 の巻き戻し)。
        return .shared(filteredEntries.filter { $0.depth == 0 })
    }

    /// いまの表示設定をまとめた絞り込み。プレビューのフォルダー一覧
    /// (FolderListingView)も同じ値を受け取り、同じ関数で適用する。表示設定は
    /// ここ 1 箇所に集約し、増えたときに片側だけ取り残されないようにする(TASK-288)。
    var listFilter: FileListFilter {
        FileListFilter(
            filterText: filterText,
            gitStatus: showChangedFilesOnly ? gitStatus : nil,
            presentedPathKey: storedSelectionPathKey
        )
    }

    /// いま適用できる git 絞り込み。次のいずれかなら nil(= 絞り込まない)。
    ///
    /// - トグルが OFF。
    /// - `gitStatus` が nil(git 管理外・取得失敗・機能無効)。**空の状態は nil ではない**ため、
    ///   変更が 1 つも無いリポジトリではきちんと絞り込みが効く。
    /// - 状態が別のディレクトリのもの。一覧の取得と git の取得は別タスクで、完了順が
    ///   保証されない。移動直後に前のリポジトリの状態で絞り込むと一覧が一瞬消えるため、
    ///   届いている状態が表示中ディレクトリのものであることを条件にする(TASK-285)。
    /// - 状態が手元の一覧のディレクトリのものでない。突き合わせ先は visibleEntries と
    ///   同じ `entriesDirectory` にする。空状態の文言はその一覧に対する説明なので、
    ///   片方だけ currentDirectory を見ると「絞り込みで空」と「対応ファイルなし」が入れ替わる。
    var activeGitChangeFilter: SidebarGitStatus? {
        listFilter.gitChangeFilter(for: entriesDirectory)
    }

    var canGoBack: Bool {
        !backHistory.isEmpty
    }

    var canGoForward: Bool {
        !forwardHistory.isEmpty
    }

    var backHistory: [HistoryEntry] = []
    var forwardHistory: [HistoryEntry] = []

    init(
        currentDirectory: URL, entries: [FileListEntry], selection: FileListEntry.ID?,
        sortOrder: SortOrder = .foldersFirst
    ) {
        self.currentDirectory = currentDirectory
        rootDirectory = currentDirectory
        entriesDirectory = currentDirectory
        self.entries = entries
        let normalizedSelection = selection?.nativeBackedFileURL
        storedSelection = normalizedSelection
        storedSelectionPathKey = normalizedSelection?.normalizedPathKey
        self.sortOrder = sortOrder
        // 各プロパティの didSet は init 中には走らないため、派生する値をここで揃える。
        entryIndex = FileListEntryIndex(entries: entries)
        lastNotifiedTarget = .undetermined
        lastNotifiedTarget = previewTarget
    }
}
