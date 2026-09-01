import AppKit

// MARK: - Menu Validation

/// メニュー有効判定が参照するウィンドウ側の状態。ウィンドウそのものではなく
/// 「判定に要る値」だけを露出させ、`ViewerMenuValidator` をウィンドウ生成なしに検証できるようにする。
@MainActor
protocol ViewerMenuValidationSource: AnyObject {
    /// いま何ができるか(ADR 0002 段 2)。有効/無効の条件はすべてこの値が持つ。
    var capabilities: ViewerCapabilities { get }
    /// ソース表示中か。⌘U の項目名(「ソースを表示」/「レンダリングを表示」)に使う。
    var isSourceMode: Bool { get }
    /// 行番号を表示中か。項目名の切り替えに使う。
    var showLineNumbers: Bool { get }
    /// 現在ファイルがブックマーク済みか。項目名の切り替えに使う。
    var isBookmarked: Bool { get }
    /// ファイル履歴を戻れるか。
    var canGoBack: Bool { get }
    /// ファイル履歴を進めるか。
    var canGoForward: Bool { get }
    /// チェックを付けるモード(⌘1〜⌘3)。
    var effectiveDisplayMode: ViewerDisplayMode { get }
    /// 差分レイアウトが左右分割か(⌘\\ のチェック状態)。
    var isDiffLayoutSideBySide: Bool { get }
    /// サイドバーが畳まれているか。⌘←(サイドバーへフォーカス)の有効判定に使う。
    var isSidebarCollapsed: Bool { get }
}

/// メインメニュー・ツールバー項目の有効判定と表示名を決める対応表。
///
/// ここが持つのは「どのセレクタがどの能力・どの項目名に対応するか」だけで、
/// **有効/無効の条件そのものは書かない**(条件は `ViewerCapabilities` の 1 箇所 / ADR 0002)。
///
/// `@objc` アクションの実体は NSResponder チェーンを辿って届く必要があるため
/// `ViewerWindowController+MenuActions.swift` に残る。ここへ移したのは判定側だけで、
/// セレクタはその実体を指す。
@MainActor
enum ViewerMenuValidator {
    /// `NSMenuItemValidation` の実装本体。担当外の項目は既定どおり有効(true)を返す。
    /// 項目名・チェック状態の更新も、判定と同じ場所で行う(片方だけ古い表示になるのを防ぐ)。
    static func validate(_ menuItem: NSMenuItem, source: some ViewerMenuValidationSource) -> Bool {
        let capabilities = source.capabilities
        if menuItem.action == #selector(ViewerWindowController.toggleSourceView(_:)) {
            menuItem.title = ViewerCommandTitles.sourceView(isSourceMode: source.isSourceMode)
            return capabilities.canToggleSourceMode
        }
        if menuItem.action == #selector(ViewerWindowController.toggleLineNumbers(_:)) {
            menuItem.title = ViewerCommandTitles.lineNumbers(isShown: source.showLineNumbers)
            return capabilities.canToggleLineNumbers
        }
        if let enabled = validateDisplayModeItem(menuItem, source: source) {
            return enabled
        }
        if menuItem.action == #selector(ViewerWindowController.toggleBookmark(_:)) {
            menuItem.title = ViewerCommandTitles.bookmark(isBookmarked: source.isBookmarked)
            return capabilities.canBookmark
        }
        if let enabled = validateFocusTraversalItem(menuItem, source: source) {
            return enabled
        }
        if menuItem.action == #selector(ViewerWindowController.goBack(_:)) {
            return source.canGoBack
        }
        if menuItem.action == #selector(ViewerWindowController.goForward(_:)) {
            return source.canGoForward
        }
        if let action = menuItem.action, findActions.contains(action) {
            return capabilities.canFind
        }
        if let enabled = validateDocumentJumpItem(menuItem, capabilities: capabilities) {
            return enabled
        }
        if let enabled = validateDocumentCommandItem(menuItem, capabilities: capabilities) {
            return enabled
        }
        return true
    }

    /// 表示モード選択(⌘1〜⌘3)とレイアウト切替(⌘\\)の validate。
    /// 自分の担当外の項目には nil を返し、呼び出し側(validate)の判定を続けさせる。
    /// サイドバーと本文の行き来（⌘← / ⌘→ / TASK-584）。担当外なら nil。
    ///
    /// **⌘← は畳んでいるときだけ無効。** 行が 1 つも描かれていないサイドバーへ
    /// フォーカスを送っても、キー操作の宛先が消えるだけになる。
    /// かつてサイドバーの「上位フォルダーへ移動」と重なっていたが、そちらを廃止したので
    /// 文脈で意味を分ける必要は無くなった（上へ出る手段は ⌘↑ と delete）。
    ///
    /// **⌘→ は常に有効。** どの種別でも「本文を読む」ことはできるので、能力では絞らない。
    private static func validateFocusTraversalItem(
        _ menuItem: NSMenuItem, source: some ViewerMenuValidationSource
    ) -> Bool? {
        if menuItem.action == #selector(ViewerWindowController.focusSidebar(_:)) {
            return !source.isSidebarCollapsed
        }
        if menuItem.action == #selector(ViewerWindowController.focusContentSurface(_:)) {
            return true
        }
        return nil
    }

    private static func validateDisplayModeItem(
        _ menuItem: NSMenuItem, source: some ViewerMenuValidationSource
    ) -> Bool? {
        if menuItem.action == #selector(ViewerWindowController.selectDisplayMode(_:)) {
            guard let mode = ViewerDisplayMode(menuItemTag: menuItem.tag) else { return false }
            menuItem.state = source.effectiveDisplayMode == mode ? .on : .off
            return source.capabilities.canSelect(mode)
        }
        if menuItem.action == #selector(ViewerWindowController.toggleDiffLayout(_:)) {
            menuItem.state = source.isDiffLayoutSideBySide ? .on : .off
            return source.capabilities.canToggleDiffLayout
        }
        return nil
    }

    /// 文書内ジャンプ(Edit メニュー)の validate。種類ごとに条件が違う
    /// (変更ブロックは差分表示中だけ)ため、項目のタグから種類を復元して引き当てる。
    /// 自分の担当外の項目には nil を返す(`validateDisplayModeItem` と同じ形)。
    private static func validateDocumentJumpItem(
        _ menuItem: NSMenuItem, capabilities: ViewerCapabilities
    ) -> Bool? {
        guard menuItem.action == #selector(ViewerWindowController.documentJump(_:)) else {
            return nil
        }
        // タグから種類を復元できない項目は、種類によらない共通条件へ落とす。
        guard let kind = DocumentJumpKind(menuItemTag: menuItem.tag) else {
            return capabilities.canJump
        }
        return capabilities.canJump(to: kind)
    }

    /// 文書に対する操作(印刷・ズーム)の validate。どれも「その能力があるか」を
    /// 引くだけなので 1 つにまとめる。担当外の項目には nil を返す
    /// (`validateDisplayModeItem` と同じ形)。
    private static func validateDocumentCommandItem(
        _ menuItem: NSMenuItem, capabilities: ViewerCapabilities
    ) -> Bool? {
        guard let action = menuItem.action else { return nil }
        if action == #selector(ViewerWindowController.printDocument(_:)) { return capabilities.canPrint }
        if zoomActions.contains(action) { return capabilities.canZoom }
        return nil
    }

    /// 検索系(⌘F / ⌘G / ⌘⇧G)。どれも同じ能力を見る。
    private static let findActions: [Selector] = [
        #selector(ViewerWindowController.find(_:)),
        #selector(ViewerWindowController.findNext(_:)),
        #selector(ViewerWindowController.findPrevious(_:)),
    ]

    /// ズーム系(拡大・縮小・等倍)。どれも同じ能力を見る。
    private static let zoomActions: [Selector] = [
        #selector(ViewerWindowController.zoomIn(_:)),
        #selector(ViewerWindowController.zoomOut(_:)),
        #selector(ViewerWindowController.resetZoom(_:)),
    ]
}

// MARK: - ViewerMenuValidationSource

/// 判定に要る値のうち、他の名前で持っているものだけをここで橋渡しする
/// (残り——capabilities / isSourceMode / isBookmarked / effectiveDisplayMode /
/// isDiffLayoutSideBySide——は既存の同名メンバーがそのまま要求を満たす)。
extension ViewerWindowController: ViewerMenuValidationSource {
    var showLineNumbers: Bool {
        store.showLineNumbers
    }

    var canGoBack: Bool {
        navigationHistory.canGoBack
    }

    var canGoForward: Bool {
        navigationHistory.canGoForward
    }

    /// 分割ビューが未配線（テストの最小構成など）なら「畳んでいない」として扱う。
    /// 有効側へ倒すのは、判定できないことを理由に操作を塞がないため。
    var isSidebarCollapsed: Bool {
        sidebarCollapsible?.isSidebarCollapsed ?? false
    }
}
