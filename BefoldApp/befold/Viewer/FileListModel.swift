import AppKit
import BefoldKit
import Foundation

/// サイドバーのファイル一覧と選択状態を保持する監視可能モデル。
/// リネームやディレクトリの変化に追従して一覧・選択を更新できるよう、
/// ウィンドウ側(ViewerWindowController)が参照型で保持して書き換える。
@MainActor
@Observable
final class FileListModel {
    var currentDirectory: URL
    /// このウィンドウでこれまでにアクティブになった最上位のディレクトリ。
    /// パスコピー機能の相対パス基準として使う(SidebarNavigator.navigateToFolder が更新)。
    var rootDirectory: URL
    /// サイドバーの一覧。代入をもって「一覧が届いた」とみなす(hasLoadedEntries)。
    var entries: [FileListEntry] {
        didSet {
            hasLoadedEntries = true
            onPresentationTargetChange?()
        }
    }

    /// 一覧が一度でも反映されたか。ウィンドウは一覧を空で作って非同期に埋めるため、
    /// それまでは「選択が一覧に無い」が「対象が確定していない」を意味する。
    /// 「選択を消してフォルダーを表示している」状態と取り違えないための区別に使う。
    private(set) var hasLoadedEntries: Bool = false

    /// プレビュー領域が提示すべき対象。ViewerContentView と ViewerWindowController が
    /// 同じ値を見るための単一の導出点(ADR 0002)。
    var previewTarget: PreviewTarget {
        PreviewTargetResolver.resolve(
            selection: selection,
            entries: entries,
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
        set { storedSelection = newValue?.nativeBackedFileURL }
    }

    private var storedSelection: FileListEntry.ID? {
        didSet { onPresentationTargetChange?() }
    }

    /// 提示対象(previewTarget)が変わりうる書き換えのあとに呼ばれる。
    /// ツールバーの view ベースアイテムは AppKit の validate を通らず、明示的に
    /// 再同期しないと古い有効状態のまま残るため、その通知点として使う(ADR 0002)。
    @ObservationIgnored var onPresentationTargetChange: (() -> Void)?
    var sortOrder: SortOrder
    /// サイドバーのアイコンボタン・メニュー・ショートカットの見た目に使う現在値。
    /// 永続化・真実の源は HiddenFilesPreference。SidebarNavigator が
    /// refreshFileList()/navigateToFolder(_:) のたびに同期する。
    var showHiddenFiles: Bool = false
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
    /// 表示中ディレクトリのファイルに対する git 状態。キーは `FileListEntry.pathKey`
    /// (正規化済み絶対パス)。git 管理外・取得失敗・機能無効時は空のまま。
    /// 取得は subprocess を伴うため SidebarNavigator が一覧更新と同じ契機でメイン外から行う。
    var gitStatuses: [String: GitFileStatus] = [:]
    /// フォルダー行のバッジ用に、配下(再帰的)の変更を集約した結果。キーは同じく
    /// `FileListEntry.pathKey`。`gitStatuses` から純関数で導けるが、行ごとに配下を
    /// 走査させないよう SidebarNavigator が同じ契機で一度だけ写像して持たせる。
    var gitFolderStatuses: [String: GitFolderStatus] = [:]

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
    var visibleEntries: [FileListEntry] {
        guard !filterText.isEmpty else { return entries }
        return entries.filter {
            $0.kind == .parentNavigation
                || WildcardMatcher.matches(pattern: filterText, in: $0.url.lastPathComponent)
        }
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
        storedSelection = selection?.nativeBackedFileURL
        self.sortOrder = sortOrder
    }
}
