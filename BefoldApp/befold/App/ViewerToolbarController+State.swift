import AppKit

/// ツールバー上の各アイテムへ現在の状態を反映する処理。
///
/// 型の外から呼んでよいのは `refreshToolbarState()` のみ。`apply*State(to:)` は
/// `ViewerToolbarController.layout` の applyState から呼ばれるため internal だが、
/// 個別に呼ばず必ず `refreshToolbarState()` を経由する。
extension ViewerToolbarController {
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
    func applyHistoryState(to item: NSToolbarItem) {
        guard let button = item.view as? HistoryButtonView, let host else { return }
        let isBack = item.itemIdentifier == Self.backItemIdentifier
        let history = host.navigationHistory
        if isBack {
            button.updateState(isEnabled: history.canGoBack, entries: history.backEntries())
        } else {
            button.updateState(isEnabled: history.canGoForward, entries: history.forwardEntries())
        }
        item.toolTip = String(localized: isBack ? "toolbar.back" : "toolbar.forward", bundle: .l10n)
    }

    /// モード切替セグメントの選択状態・有効/無効を現在のファイル種別に合わせて反映する。
    /// プレビューできない種別(.code)ではソース側を、テキストソースを持たない
    /// バイナリ種別(画像・PDF)ではプレビュー側を、それぞれ選択済み・唯一の有効状態にする。
    /// 差分セグメントのアイコン・ツールチップは現在の差分レイアウトで変わるため、
    /// 生成時だけでなく再同期のたびに入れ直す(⌘\\ やメニューからの変更に追従させる)。
    func applyModeToggleState(to item: NSToolbarItem) {
        guard let host, let segmentedControl = item.view as? NSSegmentedControl else { return }
        let isSideBySide = host.isDiffLayoutSideBySide
        for (index, mode) in ModeSegments.all.enumerated() {
            segmentedControl.setEnabled(host.canSelect(mode), forSegment: index)
            let label = Self.segmentLabel(for: mode, isSideBySide: isSideBySide)
            segmentedControl.setImage(
                Self.segmentImage(for: mode, isSideBySide: isSideBySide, label: label),
                forSegment: index
            )
            segmentedControl.setToolTip(label, forSegment: index)
        }
        segmentedControl.selectedSegment = ModeSegments.all.firstIndex(of: host.effectiveDisplayMode) ?? 0
    }

    /// セグメントのツールチップ兼アクセシビリティ説明。差分だけは現在のレイアウトまで伝える。
    /// ViewerToolbarController+ToolbarDelegate の生成処理からも使うため internal。
    static func segmentLabel(for mode: ViewerDisplayMode, isSideBySide: Bool) -> String {
        mode == .diff
            ? ViewerCommandTitles.diffMode(isSideBySide: isSideBySide)
            : String(localized: ModeSegments.labelKey(for: mode), bundle: .l10n)
    }

    /// セグメントのアイコン。`refreshToolbarState` は再読込のたびに走るため、
    /// シンボル名ごとに 1 枚だけ作って使い回す。
    private static var segmentImages: [String: NSImage] = [:]

    /// シンボル名ごとに 1 枚だけ作って使い回すため、同じ (mode, isSideBySide) からは
    /// 常に同一インスタンスが返る。テストはこの同一性でアイテムへの反映を確かめる。
    static func segmentImage(for mode: ViewerDisplayMode, isSideBySide: Bool, label: String) -> NSImage {
        let symbol = ModeSegments.symbol(for: mode, isSideBySide: isSideBySide)
        if let cached = segmentImages[symbol] {
            cached.accessibilityDescription = label
            return cached
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
        segmentImages[symbol] = image
        return image
    }

    /// 行番号アイテムの有効/無効・オンオフ表示・ツールチップを現在の表示状態に合わせて反映する。
    func applyLineNumbersState(to item: NSToolbarItem) {
        guard let host, let button = item.view as? NSButton else { return }
        button.isEnabled = host.capabilities.canToggleLineNumbers
        // オン状態はボタンの塗り潰し(.pushOnPushOff)ではなくシンボルの
        // アクセント色で示し、隣のモード切替セグメントと色味を揃える
        button.contentTintColor = host.store.showLineNumbers ? .controlAccentColor : nil
        item.toolTip = ViewerCommandTitles.lineNumbers(isShown: host.store.showLineNumbers)
    }

    /// ブックマークアイテムのアイコン(bookmark/bookmark.fill)・色・ツールチップを
    /// 現在ファイルのブックマーク状態に合わせて反映する。
    func applyBookmarkState(to item: NSToolbarItem) {
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
}
