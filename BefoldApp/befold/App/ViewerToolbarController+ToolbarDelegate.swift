import AppKit

/// NSToolbarDelegate 準拠と、宣言(ToolbarItemSpec)からのアイテム・ビュー生成。
extension ViewerToolbarController {
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
        let isSideBySide = host?.isDiffLayoutSideBySide ?? false
        let labels = ModeSegments.all.map { Self.segmentLabel(for: $0, isSideBySide: isSideBySide) }
        let images = zip(ModeSegments.all, labels).map { mode, label in
            Self.segmentImage(for: mode, isSideBySide: isSideBySide, label: label)
        }
        let segmentedControl = NSSegmentedControl(
            images: images,
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeSegmentChanged(_:))
        )
        // 差分セグメントはレイアウトでアイコンが入れ替わる。シンボルごとの
        // 固有幅に引きずられてセグメント幅が動かないよう、幅を明示的に固定する。
        for (index, label) in labels.enumerated() {
            segmentedControl.setWidth(Self.segmentWidth, forSegment: index)
            segmentedControl.setToolTip(label, forSegment: index)
        }
        return segmentedControl
    }

    /// セグメント 1 つ分の幅。アイコンが入れ替わっても幅が動かないよう固定する。
    private static let segmentWidth: CGFloat = 32

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.layout.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.layout.map(\.identifier) + [.space]
    }
}
