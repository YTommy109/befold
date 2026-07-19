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
}

/// モード切替セグメントコントロールのセグメント位置(0=プレビュー, 1=ソース)。
private enum ModeSegment: Int, Sendable {
    case preview = 0
    case source = 1
}

/// ViewerWindowController のツールバー(モード切替・戻る/進む・行番号)の構築とライブ状態更新を担う。
/// NSToolbarDelegate 準拠には NSObject 継承が必須のため、独立クラスとして切り出す。
@MainActor
final class ViewerToolbarController: NSObject, NSToolbarDelegate {
    static let modeToggleItemIdentifier = NSToolbarItem.Identifier("modeToggle")
    static let backItemIdentifier = NSToolbarItem.Identifier("historyBack")
    static let forwardItemIdentifier = NSToolbarItem.Identifier("historyForward")
    static let lineNumbersItemIdentifier = NSToolbarItem.Identifier("lineNumbers")

    /// ツールバーが所属するウィンドウ。生成済みアイテムの検索(window.toolbar.items)に使う。
    private weak var window: NSWindow?
    /// 状態参照・アクション委譲の先。循環参照を避けるため weak。
    private weak var host: ViewerToolbarHost?

    init(window: NSWindow, host: ViewerToolbarHost) {
        self.window = window
        self.host = host
    }

    // MARK: - History State

    /// 履歴状態の変化をツールバーの戻る/進むアイテムへ反映する。
    /// SidebarNavigator からの通知(ViewerWindowController 経由)を受けて呼ばれる。
    func historyStateDidChange() {
        window?.toolbar?.items
            .filter {
                $0.itemIdentifier == Self.backItemIdentifier
                    || $0.itemIdentifier == Self.forwardItemIdentifier
            }
            .forEach { updateHistoryToolbarItem($0) }
    }

    /// 戻る/進むアイテム 1 つへ現在の履歴状態を反映する。
    private func updateHistoryToolbarItem(_ item: NSToolbarItem) {
        guard let button = item.view as? HistoryButtonView, let host else { return }
        if item.itemIdentifier == Self.backItemIdentifier {
            button.updateState(isEnabled: host.fileListModel.canGoBack, entries: host.fileListModel.backHistory)
        } else {
            button.updateState(isEnabled: host.fileListModel.canGoForward, entries: host.fileListModel.forwardHistory)
        }
    }

    // MARK: - Mode Toggle / Line Numbers Appearance

    /// モード切替セグメントの選択状態・有効/無効を現在のファイル種別に合わせて更新する。
    /// プレビューできない種別(.code)ではソース側を、テキストソースを持たない
    /// バイナリ種別(画像・PDF)ではプレビュー側を、それぞれ選択済み・唯一の有効状態にする。
    /// - Parameter item: 更新対象のツールバーアイテム。省略時は window.toolbar から検索する
    ///   (生成中でまだ toolbar.items に含まれないアイテムを更新する場合は明示的に渡すこと)。
    func updateModeToggleAppearance(_ item: NSToolbarItem? = nil) {
        guard let host,
              let item = item ?? window?.toolbar?.items.first(where: {
                  $0.itemIdentifier == Self.modeToggleItemIdentifier
              }), let segmentedControl = item.view as? NSSegmentedControl
        else { return }
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

    /// 行番号アイテムの有効/無効・オンオフ表示・ツールチップを現在の表示状態に合わせて更新する。
    /// - Parameter item: 更新対象。省略時は window.toolbar から検索する
    ///   (生成中でまだ toolbar.items に含まれないアイテムを更新する場合は明示的に渡すこと)。
    func updateLineNumbersToolbarItem(_ item: NSToolbarItem? = nil) {
        guard let host,
              let item = item ?? window?.toolbar?.items.first(where: {
                  $0.itemIdentifier == Self.lineNumbersItemIdentifier
              }), let button = item.view as? NSButton
        else { return }
        button.isEnabled = host.store.showsCodeContent
        // オン状態はボタンの塗り潰し(.pushOnPushOff)ではなくシンボルの
        // アクセント色で示し、隣のモード切替セグメントと色味を揃える
        button.contentTintColor = host.store.showLineNumbers ? .controlAccentColor : nil
        item.toolTip = host.store.showLineNumbers
            ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
            : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
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
        if itemIdentifier == Self.backItemIdentifier || itemIdentifier == Self.forwardItemIdentifier {
            return makeHistoryToolbarItem(itemIdentifier)
        }
        if itemIdentifier == Self.lineNumbersItemIdentifier {
            return makeLineNumbersToolbarItem()
        }
        guard itemIdentifier == Self.modeToggleItemIdentifier else { return nil }
        let previewLabel = String(localized: "toolbar.mode.preview", bundle: .l10n)
        let sourceLabel = String(localized: "toolbar.mode.source", bundle: .l10n)
        // ラベル文字列は状態に関わらず固定なので、セグメント幅が切替でジッターしない。
        let segmentedControl = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: previewLabel)!,
                NSImage(
                    systemSymbolName: "chevron.left.forwardslash.chevron.right",
                    accessibilityDescription: sourceLabel
                )!,
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeSegmentChanged(_:))
        )
        segmentedControl.setToolTip(previewLabel, forSegment: ModeSegment.preview.rawValue)
        segmentedControl.setToolTip(sourceLabel, forSegment: ModeSegment.source.rawValue)

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = String(localized: "toolbar.mode.group", bundle: .l10n)
        item.view = segmentedControl
        updateModeToggleAppearance(item)
        return item
    }

    /// 戻る/進むのツールバーアイテムを生成する。生成時点の履歴状態を初期反映する。
    private func makeHistoryToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let isBack = identifier == Self.backItemIdentifier
        let label = isBack
            ? String(localized: "toolbar.back", bundle: .l10n)
            : String(localized: "toolbar.forward", bundle: .l10n)
        let button = HistoryButtonView(
            systemImage: isBack ? "chevron.left" : "chevron.right",
            accessibilityLabel: label,
            primaryOffset: isBack ? -1 : 1,
            onNavigate: { [weak self] offset in self?.host?.navigateHistory(by: offset) }
        )
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.view = button
        // Finder と同じく、ナビゲーション項目としてウィンドウタイトル(ファイル名)より
        // 先頭側(コンテンツ領域の左端)に配置する
        item.isNavigational = true
        // ウィンドウが狭まりオーバーフロー(») メニューに収容される際、view ベースの
        // アイテムは menuFormRepresentation が無いと action の無い死んだ項目になるため設定する。
        let menuItem = NSMenuItem(
            title: label,
            action: isBack
                ? #selector(goBackFromMenu(_:)) : #selector(goForwardFromMenu(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        item.menuFormRepresentation = menuItem
        updateHistoryToolbarItem(item)
        return item
    }

    /// 行番号トグルのツールバーアイテムを生成する。常時表示し、
    /// コード系コンテンツ表示中(showsCodeContent)以外は無効にする。
    private func makeLineNumbersToolbarItem() -> NSToolbarItem {
        let label = String(localized: "menu.view.showLineNumbers", bundle: .l10n)
        let button = NSButton(
            image: NSImage(systemSymbolName: "list.number", accessibilityDescription: label)!,
            target: self,
            action: #selector(lineNumbersItemClicked(_:))
        )
        button.bezelStyle = .texturedRounded
        let item = NSToolbarItem(itemIdentifier: Self.lineNumbersItemIdentifier)
        item.label = label
        item.view = button
        // ウィンドウが狭まりオーバーフロー(») メニューに収容される際、view ベースの
        // アイテムは menuFormRepresentation が無いと action の無い死んだ項目になるため設定する。
        let menuItem = NSMenuItem(title: label, action: #selector(lineNumbersItemClicked(_:)), keyEquivalent: "")
        menuItem.target = self
        item.menuFormRepresentation = menuItem
        updateLineNumbersToolbarItem(item)
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            .flexibleSpace, Self.lineNumbersItemIdentifier, Self.modeToggleItemIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            Self.lineNumbersItemIdentifier, Self.modeToggleItemIdentifier,
            .flexibleSpace, .space,
        ]
    }
}
