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
    var entries: [FileListEntry] {
        didSet {
            hasLoadedEntries = true
            entryIndex = FileListEntryIndex(entries: entries)
            notifyPresentationTargetChangeIfNeeded()
        }
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
        didSet { notifyPresentationTargetChangeIfNeeded() }
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
    var gitStatus: SidebarGitStatus?

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

    /// フィルター適用後にサイドバーへ表示するエントリ。`entries`(ディスク由来の一覧)は
    /// 保持したまま、この算出側だけで絞り込む。`.parentNavigation` はフィルター文字列に
    /// 関わらず常に含める(上位フォルダへの移動手段を残すため)。
    /// git 変更での絞り込み(showChangedFilesOnly)も AND で併用する。
    var visibleEntries: [FileListEntry] {
        listFilter.apply(to: entries, in: currentDirectory)
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
    var activeGitChangeFilter: SidebarGitStatus? {
        listFilter.gitChangeFilter(for: currentDirectory)
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
