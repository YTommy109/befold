import AppKit

/// ViewerToolbarController がツールバー構築・アクション委譲のために参照する先。
/// ViewerWindowController が実装する。循環参照を避けるため ViewerToolbarController からは weak 参照する。
@MainActor
protocol ViewerToolbarHost: AnyObject {
    /// サイドバーのファイル一覧と選択状態。
    var fileListModel: FileListModel { get }
    /// 戻る/進むアイテムの有効状態と履歴メニューの中身。写しを経由せずここを読む(TASK-458)。
    var navigationHistory: NavigationHistory { get }
    /// 表示状態(ファイル種別・ソース表示可否・行番号表示)。
    var store: ViewerStore { get }
    /// いま何ができるか。ツールバーの有効/無効はここだけを見る(ADR 0002)。
    var capabilities: ViewerCapabilities { get }
    /// いまの表示モード。セグメントの選択位置に使う。
    var effectiveDisplayMode: ViewerDisplayMode { get }
    /// モード切替セグメントの選択変更を反映する。
    func setDisplayMode(_ newValue: ViewerDisplayMode)
    /// そのモードをいま選べるか(セグメントごとの有効/無効に使う)。
    func canSelect(_ mode: ViewerDisplayMode) -> Bool
    /// 差分レイアウト(インライン/左右分割)の切替。差分表示中に差分セグメントを
    /// 再クリックしたときに呼ばれる。
    func toggleDiffLayout(_ sender: Any?)
    /// 差分レイアウトが左右分割か。差分セグメントのアイコン・説明に使う。
    var isDiffLayoutSideBySide: Bool { get }
    /// 戻る/進むアイテム・メニュー表現から呼ばれる履歴ナビゲーション。
    func navigateHistory(by offset: Int)
    /// 行番号ボタン・メニュー表現から呼ばれる行番号表示トグル。
    func toggleLineNumbers(_ sender: Any?)
    /// 現在ファイルがブックマーク済みかどうか。ブックマークボタンのアイコン・色に使う。
    var isBookmarked: Bool { get }
    /// ブックマークボタン・メニュー表現から呼ばれるブックマークトグル。
    func toggleBookmark(_ sender: Any?)
}

/// ツールバーアイテム 1 つの identity(識別子・シンボル・ラベル・アクション・状態反映規則)を
/// 1 箇所で宣言する記述。生成(makeItem)と再同期(refreshToolbarState)の双方がこの記述だけを見るため、
/// アイテムを追加・変更するときに触る箇所は ViewerToolbarController.layout の 1 行で済む。
///
/// internal なのは ViewerToolbarController+ToolbarDelegate がアイテム生成に使うため。
/// 生成・状態反映の実装以外から参照しない。
@MainActor
struct ToolbarItemSpec {
    /// アイテムの view の種類と、その生成に必要なシンボル・アクション。
    enum ViewKind {
        /// 単一シンボルのボタン(行番号・ブックマーク)。
        case button(symbol: String, action: Selector)
        /// 履歴ナビゲーション用ボタン。primaryOffset の符号で戻る/進むを決める。
        case historyButton(symbol: String, offset: Int)
        /// レンダリング/ソース/差分のモード切替セグメント。
        case modeSegments
    }

    let identifier: NSToolbarItem.Identifier
    /// アイテムのラベル(および多くのアイテムのツールチップ)のローカライズキー。
    let labelKey: String.LocalizationValue
    let view: ViewKind
    /// オーバーフロー(»)メニュー項目に割り当てるアクション。
    /// nil なら menuFormRepresentation を作らない(セグメントコントロールは分解できないため対象外)。
    let menuAction: Selector?
    /// ナビゲーション項目としてウィンドウタイトルより先頭側へ配置するか。
    var isNavigational = false
    /// 生成済みアイテムへ現在の状態(有効/無効・アイコン・色・ツールチップ)を反映する規則。
    let applyState: (ViewerToolbarController, NSToolbarItem) -> Void
}

/// ツールバーの構成要素。順序をそのまま既定の表示順として使うため、
/// アイテムと AppKit 標準アイテム(サイドバー開閉・スペーサー)を同じ並びで表現する。
///
/// internal なのは ToolbarItemSpec と同じ理由(分割した extension から参照するため)。
@MainActor
enum ToolbarEntry {
    case system(NSToolbarItem.Identifier)
    case item(ToolbarItemSpec)

    var identifier: NSToolbarItem.Identifier {
        switch self {
        case let .system(identifier): identifier
        case let .item(spec): spec.identifier
        }
    }

    var spec: ToolbarItemSpec? {
        switch self {
        case .system: nil
        case let .item(spec): spec
        }
    }
}

/// ViewerWindowController のツールバー(モード切替・戻る/進む・行番号・ブックマーク)の
/// 構築とライブ状態更新を担う。
/// NSToolbarDelegate 準拠には NSObject 継承が必須のため、独立クラスとして切り出す。
@MainActor
final class ViewerToolbarController: NSObject, NSToolbarDelegate {
    static let modeToggleItemIdentifier = NSToolbarItem.Identifier("modeToggle")
    static let backItemIdentifier = NSToolbarItem.Identifier("historyBack")
    static let forwardItemIdentifier = NSToolbarItem.Identifier("historyForward")
    static let lineNumbersItemIdentifier = NSToolbarItem.Identifier("lineNumbers")
    static let bookmarkItemIdentifier = NSToolbarItem.Identifier("bookmark")

    /// ツールバー構成。この並びが既定の表示順になり、生成・再同期・許可アイテム一覧は
    /// すべてここから導出する。
    ///
    /// 読み取り専用の構成表。分割した extension(+State / +ToolbarDelegate)から参照するため
    /// internal だが、書き換えてよい場所は無く、変更はこの宣言そのものを直すことで行う。
    ///
    /// 差分機能のフィーチャーゲートはこの構成を変えない。差分レイアウトの切替は
    /// 独立したアイテムではなくモード切替セグメント（差分セグメントの再クリック）が担い、
    /// 差分セグメント自体の有無は `ModeSegments.all` が決めるため。
    static let layout: [ToolbarEntry] = [
        .system(.toggleSidebar), .system(.sidebarTrackingSeparator),
        .item(ToolbarItemSpec(
            identifier: backItemIdentifier,
            labelKey: "toolbar.back",
            view: .historyButton(symbol: "chevron.left", offset: -1),
            menuAction: #selector(goBackFromMenu(_:)),
            // Finder と同じく、ナビゲーション項目としてウィンドウタイトル(ファイル名)より
            // 先頭側(コンテンツ領域の左端)に配置する
            isNavigational: true,
            applyState: { $0.applyHistoryState(to: $1) }
        )),
        .item(ToolbarItemSpec(
            identifier: forwardItemIdentifier,
            labelKey: "toolbar.forward",
            view: .historyButton(symbol: "chevron.right", offset: 1),
            menuAction: #selector(goForwardFromMenu(_:)),
            isNavigational: true,
            applyState: { $0.applyHistoryState(to: $1) }
        )),
        .system(.flexibleSpace),
        .item(ToolbarItemSpec(
            identifier: lineNumbersItemIdentifier,
            labelKey: "menu.view.showLineNumbers",
            view: .button(symbol: "list.number", action: #selector(lineNumbersItemClicked(_:))),
            menuAction: #selector(lineNumbersItemClicked(_:)),
            applyState: { $0.applyLineNumbersState(to: $1) }
        )),
        .item(ToolbarItemSpec(
            identifier: modeToggleItemIdentifier,
            labelKey: "toolbar.mode.group",
            view: .modeSegments,
            menuAction: nil,
            applyState: { $0.applyModeToggleState(to: $1) }
        )),
        .item(ToolbarItemSpec(
            identifier: bookmarkItemIdentifier,
            labelKey: "menu.view.addBookmark",
            view: .button(symbol: "bookmark", action: #selector(bookmarkItemClicked(_:))),
            menuAction: #selector(bookmarkItemClicked(_:)),
            applyState: { $0.applyBookmarkState(to: $1) }
        )),
    ]

    /// ツールバーが所属するウィンドウ。生成済みアイテムの検索(window.toolbar.items)に使う。
    /// 分割した extension から参照するため internal。この型の外からは触らない。
    weak var window: NSWindow?
    /// 状態参照・アクション委譲の先。循環参照を避けるため weak。
    /// 分割した extension から参照するため internal。この型の外からは触らない。
    weak var host: ViewerToolbarHost?

    /// ツールバーの生成・デリゲート設定・ウィンドウへの取り付けまでをここで行う。
    ///
    /// この 3 手順には順序制約があり、`delegate` を設定する前に `window.toolbar` へ
    /// 代入するとアイテムが空のままになる。呼び出し側で 3 行に並べると順序を入れ替えても
    /// コンパイルは通ってしまうため、初期化子の中へ閉じて破れない形にしている。
    init(window: NSWindow, host: ViewerToolbarHost) {
        self.window = window
        self.host = host
        super.init()
        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window.toolbarStyle = .unified
        window.toolbar = toolbar
    }
}
