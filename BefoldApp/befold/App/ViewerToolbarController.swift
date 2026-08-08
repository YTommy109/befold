import AppKit

/// ViewerToolbarController がツールバー構築・アクション委譲のために参照する先。
/// ViewerWindowController が実装する。循環参照を避けるため ViewerToolbarController からは weak 参照する。
@MainActor
protocol ViewerToolbarHost: AnyObject {
    /// サイドバーのファイル一覧と選択状態(戻る/進むアイテムの有効状態・履歴に使う)。
    var fileListModel: FileListModel { get }
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
    /// 差分レイアウト(上下/左右)の切替。ツールバーのレイアウトトグルから呼ばれる。
    func toggleDiffLayout(_ sender: Any?)
    /// 差分レイアウトが左右分割か。トグルのアイコン・色に使う。
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

/// モード切替セグメントに並べる表示モードと、その順序。
///
/// セグメントの添字はこの配列の添字で解決し、`ViewerDisplayMode` の値そのものからは導かない。
/// 差分セグメントはフィーチャーゲートが無効なビルドでは**存在しない**ため、
/// モードと添字の対応が固定ではないからである(添字を列挙の rawValue に直結させると、
/// stable ビルドでソースを選んだつもりで差分が選ばれるような静かな取り違えになる)。
@MainActor
enum ModeSegments {
    static let all: [ViewerDisplayMode] = modes(isSourceDiffEnabled: FeatureGate.isSourceDiffEnabled)

    /// テスト可能な純粋判定。実ビルドではゲートが片側に固定されるため、両分岐はここで検証する
    /// （ゲート越しの検証は動いているビルドの側しか通らない）。
    static func modes(isSourceDiffEnabled: Bool) -> [ViewerDisplayMode] {
        isSourceDiffEnabled ? [.rendered, .source, .diff] : [.rendered, .source]
    }

    /// セグメントの表示に使う SF Symbol 名とツールチップのローカライズキー。
    static func symbol(for mode: ViewerDisplayMode) -> String {
        switch mode {
        case .rendered: "doc.richtext"
        case .source: "chevron.left.forwardslash.chevron.right"
        case .diff: "plus.forwardslash.minus"
        }
    }

    static func labelKey(for mode: ViewerDisplayMode) -> String.LocalizationValue {
        switch mode {
        case .rendered: "toolbar.mode.preview"
        case .source: "toolbar.mode.source"
        case .diff: "toolbar.mode.diff"
        }
    }
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
    static let diffLayoutItemIdentifier = NSToolbarItem.Identifier("diffLayout")

    /// 実ビルドのツールバー構成。生成・再同期・許可アイテム一覧はすべてここから導出する。
    private static let layout: [ToolbarEntry] = layout(isSourceDiffEnabled: FeatureGate.isSourceDiffEnabled)

    /// ゲート値を引数で受けるツールバー構成。この並びが既定の表示順になる。
    /// 実ビルドではゲートが片側に固定されるため、両分岐はここで検証する
    /// （`defaultItemIdentifiers(isSourceDiffEnabled:)` 経由）。
    private static func layout(isSourceDiffEnabled: Bool) -> [ToolbarEntry] {
        ([
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
            // 差分レイアウトのトグルは差分機能そのものの一部なので、ゲートが無効なビルドでは
            // layout に載せない(載せて無効化するのではなく、存在させない)。
            isSourceDiffEnabled ? .item(ToolbarItemSpec(
                identifier: diffLayoutItemIdentifier,
                labelKey: "menu.view.diffSideBySide",
                view: .button(symbol: "rectangle.split.2x1", action: #selector(diffLayoutItemClicked(_:))),
                menuAction: #selector(diffLayoutItemClicked(_:)),
                applyState: { $0.applyDiffLayoutState(to: $1) }
            )) : nil,
            .item(ToolbarItemSpec(
                identifier: bookmarkItemIdentifier,
                labelKey: "menu.view.addBookmark",
                view: .button(symbol: "bookmark", action: #selector(bookmarkItemClicked(_:))),
                menuAction: #selector(bookmarkItemClicked(_:)),
                applyState: { $0.applyBookmarkState(to: $1) }
            )),
        ] as [ToolbarEntry?]).compactMap(\.self)
    }

    /// ゲート値ごとの既定アイテム並び。ゲート OFF 相当の構成
    /// （差分レイアウト項目が存在しないこと）をライブなゲート値に依らず検証するための入口。
    static func defaultItemIdentifiers(isSourceDiffEnabled: Bool) -> [NSToolbarItem.Identifier] {
        layout(isSourceDiffEnabled: isSourceDiffEnabled).map(\.identifier)
    }

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
        for (index, mode) in ModeSegments.all.enumerated() {
            segmentedControl.setEnabled(host.canSelect(mode), forSegment: index)
        }
        segmentedControl.selectedSegment = ModeSegments.all.firstIndex(of: host.effectiveDisplayMode) ?? 0
    }

    /// 差分レイアウトトグルの有効/無効・オンオフ表示・ツールチップを反映する。
    /// 差分表示を選んでいない間は無効にする(消すとツールバーの幅が動くため、出したまま無効化する)。
    private func applyDiffLayoutState(to item: NSToolbarItem) {
        guard let host, let button = item.view as? NSButton else { return }
        button.isEnabled = host.capabilities.canToggleDiffLayout
        button.contentTintColor = host.isDiffLayoutSideBySide ? .controlAccentColor : nil
        item.toolTip = String(localized: "menu.view.diffSideBySide", bundle: .l10n)
    }

    /// 行番号アイテムの有効/無効・オンオフ表示・ツールチップを現在の表示状態に合わせて反映する。
    private func applyLineNumbersState(to item: NSToolbarItem) {
        guard let host, let button = item.view as? NSButton else { return }
        button.isEnabled = host.capabilities.canToggleLineNumbers
        // オン状態はボタンの塗り潰し(.pushOnPushOff)ではなくシンボルの
        // アクセント色で示し、隣のモード切替セグメントと色味を揃える
        button.contentTintColor = host.store.showLineNumbers ? .controlAccentColor : nil
        item.toolTip = ViewerCommandTitles.lineNumbers(isShown: host.store.showLineNumbers)
    }

    /// ブックマークアイテムのアイコン(bookmark/bookmark.fill)・色・ツールチップを
    /// 現在ファイルのブックマーク状態に合わせて反映する。
    private func applyBookmarkState(to item: NSToolbarItem) {
        guard let host, let button = item.view as? NSButton else { return }
        button.isEnabled = host.capabilities.canBookmark
        let isBookmarked = host.isBookmarked
        let label = ViewerCommandTitles.bookmark(isBookmarked: isBookmarked)
        button.image = NSImage(
            systemSymbolName: isBookmarked ? "bookmark.fill" : "bookmark", accessibilityDescription: label
        )
        button.contentTintColor = isBookmarked ? .controlAccentColor : nil
        item.toolTip = label
    }

    // MARK: - Action Targets

    /// モード切替セグメントコントロールの選択変更を受けて呼ばれる。
    @objc private func modeSegmentChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard ModeSegments.all.indices.contains(index) else { return }
        host?.setDisplayMode(ModeSegments.all[index])
    }

    /// 差分レイアウトボタン・メニュー表現の共通アクション。host へトグルを委譲する。
    @objc private func diffLayoutItemClicked(_ sender: Any?) {
        host?.toggleDiffLayout(sender)
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
        case .modeSegments:
            return makeModeSegmentedControl()
        }
    }

    /// レンダリング/ソース(/差分)のモード切替セグメントコントロールを生成する。
    /// セグメントの並びと個数は ModeSegments.all だけが決める。
    private func makeModeSegmentedControl() -> NSSegmentedControl {
        let labels = ModeSegments.all.map { String(localized: ModeSegments.labelKey(for: $0), bundle: .l10n) }
        let images = zip(ModeSegments.all, labels).map { mode, label in
            NSImage(systemSymbolName: ModeSegments.symbol(for: mode), accessibilityDescription: label)!
        }
        // ラベル文字列は状態に関わらず固定なので、セグメント幅が切替でジッターしない。
        let segmentedControl = NSSegmentedControl(
            images: images,
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeSegmentChanged(_:))
        )
        for (index, label) in labels.enumerated() {
            segmentedControl.setToolTip(label, forSegment: index)
        }
        return segmentedControl
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.layout.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.layout.map(\.identifier) + [.space]
    }
}
