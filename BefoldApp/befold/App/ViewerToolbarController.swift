import AppKit

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
