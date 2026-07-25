import AppKit

/// ViewerToolbarController がツールバー構築・アクション委譲のために参照する先。
/// ViewerWindowController が実装する。循環参照を避けるため ViewerToolbarController からは weak 参照する。
@MainActor
protocol ViewerToolbarHost: AnyObject {
    /// サイドバーのファイル一覧と選択状態(戻る/進むアイテムの有効状態・履歴に使う)。
    var fileListModel: FileListModel { get }
    /// 表示状態(ファイル種別・ソース表示可否・行番号表示)。
    var store: ViewerStore { get }
    /// 現在のソース表示モード。モード切替セグメントの初期選択に使う。
    var isSourceMode: Bool { get }
    /// モード切替セグメントの選択変更を反映する。
    func setSourceMode(_ newValue: Bool)
    /// 戻る/進むアイテム・メニュー表現から呼ばれる履歴ナビゲーション。
    func navigateHistory(by offset: Int)
    /// 行番号ボタン・メニュー表現から呼ばれる行番号表示トグル。
    func toggleLineNumbers(_ sender: Any?)
    /// 現在ファイルがブックマーク済みかどうか。ブックマークボタンのアイコン・色に使う。
    var isBookmarked: Bool { get }
    /// ブックマークボタン・メニュー表現から呼ばれるブックマークトグル。
    func toggleBookmark(_ sender: Any?)
}

/// モード切替セグメントコントロールのセグメント位置(0=プレビュー, 1=ソース)。
private enum ModeSegment: Int, Sendable {
    case preview = 0
    case source = 1
}

/// ツールバーアイテム 1 つの identity(識別子・シンボル・ラベル・アクション・状態反映規則)を
/// 1 箇所で宣言する記述。生成(makeItem)と再同期(refreshToolbarState)の双方がこの記述だけを見るため、
/// アイテムを追加・変更するときに触る箇所は ViewerToolbarController.layout の 1 行で済む。
@MainActor
private struct ToolbarItemSpec {
    /// アイテムの view の種類と、その生成に必要なシンボル・アクション。
    enum ViewKind {
        /// 単一シンボルのボタン(行番号・ブックマーク)。
        case button(symbol: String, action: Selector)
        /// 履歴ナビゲーション用ボタン。primaryOffset の符号で戻る/進むを決める。
        case historyButton(symbol: String, offset: Int)
        /// プレビュー/ソースのモード切替セグメント。
        case modeSegments(previewSymbol: String, sourceSymbol: String)
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
@MainActor
private enum ToolbarEntry {
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

    /// ツールバー構成の唯一の情報源。この並びが既定の表示順になり、
    /// 生成・再同期・許可アイテム一覧はすべてここから導出する。
    private static let layout: [ToolbarEntry] = [
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
            view: .modeSegments(
                previewSymbol: "doc.richtext", sourceSymbol: "chevron.left.forwardslash.chevron.right"
            ),
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
    private weak var window: NSWindow?
    /// 状態参照・アクション委譲の先。循環参照を避けるため weak。
    private weak var host: ViewerToolbarHost?

    init(window: NSWindow, host: ViewerToolbarHost) {
        self.window = window
        self.host = host
    }

    // MARK: - State Synchronization

    /// 現在の状態を、ツールバー上の全アイテムへ一括で反映する。
    /// 状態を変える側(履歴移動・モード切替・行番号/ブックマークのトグル・
    /// 読み込み完了・CLI からの表示オプション上書き)はすべてここだけを呼ぶ。
    /// アイテムごとの反映規則は layout の applyState に集約されているため、
    /// 新しいアイテムや新しい状態が増えても呼び出し側は変わらない。
    func refreshToolbarState() {
        guard let items = window?.toolbar?.items else { return }
        for item in items {
            Self.layout.first { $0.identifier == item.itemIdentifier }?.spec?.applyState(self, item)
        }
    }

    /// 戻る/進むアイテム 1 つへ現在の履歴状態とツールチップを反映する。
    private func applyHistoryState(to item: NSToolbarItem) {
        guard let button = item.view as? HistoryButtonView, let host else { return }
        let isBack = item.itemIdentifier == Self.backItemIdentifier
        if isBack {
            button.updateState(isEnabled: host.fileListModel.canGoBack, entries: host.fileListModel.backHistory)
        } else {
            button.updateState(isEnabled: host.fileListModel.canGoForward, entries: host.fileListModel.forwardHistory)
        }
        item.toolTip = String(localized: isBack ? "toolbar.back" : "toolbar.forward", bundle: .l10n)
    }

    /// モード切替セグメントの選択状態・有効/無効を現在のファイル種別に合わせて反映する。
    /// プレビューできない種別(.code)ではソース側を、テキストソースを持たない
    /// バイナリ種別(画像・PDF)ではプレビュー側を、それぞれ選択済み・唯一の有効状態にする。
    private func applyModeToggleState(to item: NSToolbarItem) {
        guard let host, let segmentedControl = item.view as? NSSegmentedControl else { return }
        let isEnabled = !host.store.isRejected
        segmentedControl.setEnabled(
            host.store.fileType.isRenderable && isEnabled, forSegment: ModeSegment.preview.rawValue
        )
        segmentedControl.setEnabled(
            !host.store.fileType.isBinaryContent && isEnabled, forSegment: ModeSegment.source.rawValue
        )
        segmentedControl.selectedSegment = (host.store.showsCodeContent ? ModeSegment.source : ModeSegment.preview)
            .rawValue
    }

    /// 行番号アイテムの有効/無効・オンオフ表示・ツールチップを現在の表示状態に合わせて反映する。
    private func applyLineNumbersState(to item: NSToolbarItem) {
        guard let host, let button = item.view as? NSButton else { return }
        button.isEnabled = host.store.showsCodeContent
        // オン状態はボタンの塗り潰し(.pushOnPushOff)ではなくシンボルの
        // アクセント色で示し、隣のモード切替セグメントと色味を揃える
        button.contentTintColor = host.store.showLineNumbers ? .controlAccentColor : nil
        item.toolTip = host.store.showLineNumbers
            ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
            : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
    }

    /// ブックマークアイテムのアイコン(bookmark/bookmark.fill)・色・ツールチップを
    /// 現在ファイルのブックマーク状態に合わせて反映する。
    private func applyBookmarkState(to item: NSToolbarItem) {
        guard let host, let button = item.view as? NSButton else { return }
        let isBookmarked = host.isBookmarked
        let label = isBookmarked
            ? String(localized: "menu.view.removeBookmark", bundle: .l10n)
            : String(localized: "menu.view.addBookmark", bundle: .l10n)
        button.image = NSImage(
            systemSymbolName: isBookmarked ? "bookmark.fill" : "bookmark", accessibilityDescription: label
        )
        button.contentTintColor = isBookmarked ? .controlAccentColor : nil
        item.toolTip = label
    }

    // MARK: - Action Targets

    /// モード切替セグメントコントロールの選択変更を受けて呼ばれる。
    @objc private func modeSegmentChanged(_ sender: NSSegmentedControl) {
        host?.setSourceMode(sender.selectedSegment == ModeSegment.source.rawValue)
    }

    /// 行番号ボタン・メニュー表現の共通アクション。host へトグルを委譲する。
    @objc private func lineNumbersItemClicked(_ sender: Any?) {
        host?.toggleLineNumbers(sender)
    }

    /// ブックマークボタン・メニュー表現の共通アクション。host へトグルを委譲する。
    @objc private func bookmarkItemClicked(_ sender: Any?) {
        host?.toggleBookmark(sender)
    }

    /// 戻るアイテムのメニュー表現から呼ばれる。
    @objc private func goBackFromMenu(_ sender: Any?) {
        host?.navigateHistory(by: -1)
    }

    /// 進むアイテムのメニュー表現から呼ばれる。
    @objc private func goForwardFromMenu(_ sender: Any?) {
        host?.navigateHistory(by: 1)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let spec = Self.layout.first(where: { $0.identifier == itemIdentifier })?.spec else { return nil }
        return makeItem(for: spec)
    }

    /// 宣言(ToolbarItemSpec)からツールバーアイテムを組み立て、生成時点の状態を初期反映する。
    private func makeItem(for spec: ToolbarItemSpec) -> NSToolbarItem {
        let label = String(localized: spec.labelKey, bundle: .l10n)
        let item = NSToolbarItem(itemIdentifier: spec.identifier)
        item.label = label
        item.view = makeView(for: spec.view, label: label)
        item.isNavigational = spec.isNavigational
        // ウィンドウが狭まりオーバーフロー(») メニューに収容される際、view ベースの
        // アイテムは menuFormRepresentation が無いと action の無い死んだ項目になるため設定する。
        if let menuAction = spec.menuAction {
            let menuItem = NSMenuItem(title: label, action: menuAction, keyEquivalent: "")
            menuItem.target = self
            item.menuFormRepresentation = menuItem
        }
        // 生成直後のアイテムはまだ toolbar.items に含まれないため、
        // refreshToolbarState() では拾えない。ここで直接反映する。
        spec.applyState(self, item)
        return item
    }

    /// 宣言された view の種類に対応するビューを生成する。
    /// - Parameter label: アイテムのラベル。ボタンのアクセシビリティ記述に使う。
    private func makeView(for kind: ToolbarItemSpec.ViewKind, label: String) -> NSView {
        switch kind {
        case let .button(symbol, action):
            let button = NSButton(
                image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!,
                target: self,
                action: action
            )
            button.bezelStyle = .texturedRounded
            return button
        case let .historyButton(symbol, offset):
            return HistoryButtonView(
                systemImage: symbol,
                accessibilityLabel: label,
                primaryOffset: offset,
                onNavigate: { [weak self] offset in self?.host?.navigateHistory(by: offset) }
            )
        case let .modeSegments(previewSymbol, sourceSymbol):
            return makeModeSegmentedControl(previewSymbol: previewSymbol, sourceSymbol: sourceSymbol)
        }
    }

    /// プレビュー/ソースのモード切替セグメントコントロールを生成する。
    private func makeModeSegmentedControl(previewSymbol: String, sourceSymbol: String) -> NSSegmentedControl {
        let previewLabel = String(localized: "toolbar.mode.preview", bundle: .l10n)
        let sourceLabel = String(localized: "toolbar.mode.source", bundle: .l10n)
        // ラベル文字列は状態に関わらず固定なので、セグメント幅が切替でジッターしない。
        let segmentedControl = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: previewSymbol, accessibilityDescription: previewLabel)!,
                NSImage(systemSymbolName: sourceSymbol, accessibilityDescription: sourceLabel)!,
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeSegmentChanged(_:))
        )
        segmentedControl.setToolTip(previewLabel, forSegment: ModeSegment.preview.rawValue)
        segmentedControl.setToolTip(sourceLabel, forSegment: ModeSegment.source.rawValue)
        return segmentedControl
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.layout.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.layout.map(\.identifier) + [.space]
    }
}
