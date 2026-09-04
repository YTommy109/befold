import AppKit
@testable import befold
import Testing

/// メニュー項目の有効判定・項目名・チェック状態が、能力(ViewerCapabilities)と
/// ウィンドウ側の状態だけから決まること(ADR 0002 段 2)を検証する。
/// ウィンドウを生成せず、`ViewerMenuValidationSource` のスタブで確かめる。
@MainActor
@Suite
struct ViewerMenuValidatorTests {
    /// 判定に要る値だけを持つスタブ。既定は「文書を提示していて何でもできる」状態。
    private final class StubSource: ViewerMenuValidationSource {
        var capabilities: ViewerCapabilities = .init(
            isPresentingDocument: true, isRejected: false, isRenderable: true,
            isBinaryContent: false, showsCodeContent: true, showsDiff: true,
            supportsSourceMode: true, supportsDiffDisplay: true, supportsFind: true,
            gitDiffAvailability: .changed, isDirectHTMLMode: false,
            isDocumentJumpEnabled: true
        )
        var isSourceMode = false
        var showLineNumbers = false
        var isBookmarked = false
        var canGoBack = false
        var canGoForward = false
        var effectiveDisplayMode: ViewerDisplayMode = .rendered
        var isDiffLayoutSideBySide = false
        var isSidebarCollapsed = false
        var isSlideMode = false
    }

    private func makeItem(_ action: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.tag = tag
        return item
    }

    @Test("担当外のセレクタは既定どおり有効のまま返す")
    func leavesUnknownSelectorsEnabled() {
        let item = makeItem(#selector(NSApplication.terminate(_:)))

        #expect(ViewerMenuValidator.validate(item, source: StubSource()))
    }

    @Test("検索・印刷・ズームは対応する能力だけを見る")
    func mapsCommandsToCapabilities() {
        let source = StubSource()
        // HTML 直接ロード中は検索だけが落ちる状態を作る。
        source.capabilities = ViewerCapabilities(
            isPresentingDocument: true, isRejected: false, isRenderable: true,
            isBinaryContent: false, showsCodeContent: true, supportsSourceMode: true,
            supportsDiffDisplay: true, supportsFind: true,
            gitDiffAvailability: .changed, isDirectHTMLMode: true,
            isDocumentJumpEnabled: true
        )

        let findItems = [
            makeItem(#selector(ViewerWindowController.find(_:))),
            makeItem(#selector(ViewerWindowController.findNext(_:))),
            makeItem(#selector(ViewerWindowController.findPrevious(_:))),
        ]
        for item in findItems {
            #expect(!ViewerMenuValidator.validate(item, source: source))
        }
        #expect(ViewerMenuValidator.validate(
            makeItem(#selector(ViewerWindowController.printDocument(_:))),
            source: source
        ))
        #expect(ViewerMenuValidator.validate(makeItem(#selector(ViewerWindowController.zoomIn(_:))), source: source))
        #expect(ViewerMenuValidator.validate(makeItem(#selector(ViewerWindowController.resetZoom(_:))), source: source))
    }

    @Test("文書内ジャンプは項目のタグが指す種類ごとに判定する")
    func mapsDocumentJumpItemsToTheirKind() {
        let source = StubSource()
        // 差分表示ではない状態(既定は showsDiff: true なので作り直す)。
        source.capabilities = ViewerCapabilities(
            isPresentingDocument: true, isRejected: false, isRenderable: true,
            isBinaryContent: false, showsCodeContent: true, showsDiff: false,
            supportsSourceMode: true, supportsDiffDisplay: true, supportsFind: true,
            gitDiffAvailability: .changed, isDirectHTMLMode: false,
            isDocumentJumpEnabled: true
        )
        let jump = #selector(ViewerWindowController.documentJump(_:))

        let heading = makeItem(jump, tag: DocumentJumpKind.heading.menuItemTag)
        let changeBlock = makeItem(jump, tag: DocumentJumpKind.changeBlock.menuItemTag)

        #expect(ViewerMenuValidator.validate(heading, source: source))
        #expect(!ViewerMenuValidator.validate(changeBlock, source: source))

        source.capabilities = StubSource().capabilities // showsDiff: true
        #expect(ViewerMenuValidator.validate(changeBlock, source: source))
    }

    @Test("フォルダー一覧の表示中は文書向けのコマンドをすべて無効にする")
    func disablesDocumentCommandsWhilePresentingFolder() {
        let source = StubSource()
        source.capabilities = .none

        let items = [
            makeItem(#selector(ViewerWindowController.printDocument(_:))),
            makeItem(#selector(ViewerWindowController.zoomOut(_:))),
            makeItem(#selector(ViewerWindowController.find(_:))),
            makeItem(#selector(ViewerWindowController.toggleSourceView(_:))),
            makeItem(#selector(ViewerWindowController.toggleLineNumbers(_:))),
            makeItem(#selector(ViewerWindowController.toggleBookmark(_:))),
        ]
        for item in items {
            #expect(!ViewerMenuValidator.validate(item, source: source))
        }
    }

    @Test("トグル項目の名前は現在の状態で入れ替わる")
    func updatesToggleTitles() {
        let source = StubSource()
        let sourceViewItem = makeItem(#selector(ViewerWindowController.toggleSourceView(_:)))
        let lineNumbersItem = makeItem(#selector(ViewerWindowController.toggleLineNumbers(_:)))
        let bookmarkItem = makeItem(#selector(ViewerWindowController.toggleBookmark(_:)))

        _ = ViewerMenuValidator.validate(sourceViewItem, source: source)
        _ = ViewerMenuValidator.validate(lineNumbersItem, source: source)
        _ = ViewerMenuValidator.validate(bookmarkItem, source: source)
        #expect(sourceViewItem.title == ViewerCommandTitles.sourceView(isSourceMode: false))
        #expect(lineNumbersItem.title == ViewerCommandTitles.lineNumbers(isShown: false))
        #expect(bookmarkItem.title == ViewerCommandTitles.bookmark(isBookmarked: false))

        source.isSourceMode = true
        source.showLineNumbers = true
        source.isBookmarked = true
        _ = ViewerMenuValidator.validate(sourceViewItem, source: source)
        _ = ViewerMenuValidator.validate(lineNumbersItem, source: source)
        _ = ViewerMenuValidator.validate(bookmarkItem, source: source)
        #expect(sourceViewItem.title == ViewerCommandTitles.sourceView(isSourceMode: true))
        #expect(lineNumbersItem.title == ViewerCommandTitles.lineNumbers(isShown: true))
        #expect(bookmarkItem.title == ViewerCommandTitles.bookmark(isBookmarked: true))
    }

    @Test("戻る/進むは履歴の可否をそのまま返す")
    func mapsHistoryItems() {
        let source = StubSource()
        let back = makeItem(#selector(ViewerWindowController.goBack(_:)))
        let forward = makeItem(#selector(ViewerWindowController.goForward(_:)))

        #expect(!ViewerMenuValidator.validate(back, source: source))
        #expect(!ViewerMenuValidator.validate(forward, source: source))

        source.canGoBack = true
        source.canGoForward = true
        #expect(ViewerMenuValidator.validate(back, source: source))
        #expect(ViewerMenuValidator.validate(forward, source: source))
    }

    @Test("表示モード項目は現在のモードにだけチェックを付け、選べるものだけを有効にする")
    func checksCurrentDisplayMode() {
        let source = StubSource()
        source.effectiveDisplayMode = .source
        // 画像・PDF 相当(ソースを持たない)。プレビューだけが選べる。
        source.capabilities = ViewerCapabilities(
            isPresentingDocument: true, isRejected: false, isRenderable: true,
            isBinaryContent: true, showsCodeContent: false, supportsSourceMode: false,
            supportsDiffDisplay: false, supportsFind: true,
            gitDiffAvailability: .changed, isDirectHTMLMode: false,
            isDocumentJumpEnabled: true
        )

        let selector = #selector(ViewerWindowController.selectDisplayMode(_:))
        for mode in ViewerDisplayMode.allCases {
            let item = makeItem(selector, tag: mode.menuItemTag)
            let enabled = ViewerMenuValidator.validate(item, source: source)

            #expect(enabled == source.capabilities.canSelect(mode))
            #expect(item.state == (mode == .source ? .on : .off))
        }
    }

    @Test("タグが表示モードに対応しない項目は無効にする")
    func rejectsUnknownDisplayModeTag() {
        let item = makeItem(#selector(ViewerWindowController.selectDisplayMode(_:)), tag: -1)

        #expect(!ViewerMenuValidator.validate(item, source: StubSource()))
    }

    @Test("差分レイアウト切替のチェックは現在のレイアウトを映す")
    func reflectsDiffLayout() {
        let source = StubSource()
        let item = makeItem(#selector(ViewerWindowController.toggleDiffLayout(_:)))

        #expect(ViewerMenuValidator.validate(item, source: source))
        #expect(item.state == .off)

        source.isDiffLayoutSideBySide = true
        #expect(ViewerMenuValidator.validate(item, source: source))
        #expect(item.state == .on)
    }

    @Test("スライドモードはサイドバーを畳んでいる間は選べない")
    func slideModeRequiresVisibleSidebar() {
        let source = StubSource()
        source.isSidebarCollapsed = true

        let item = makeItem(#selector(ViewerWindowController.toggleSlideMode(_:)))

        #expect(!ViewerMenuValidator.validate(item, source: source))
    }

    @Test("スライドモードのチェックは窓の状態をそのまま映す")
    func slideModeReflectsWindowState() {
        let source = StubSource()
        let item = makeItem(#selector(ViewerWindowController.toggleSlideMode(_:)))

        #expect(ViewerMenuValidator.validate(item, source: source))
        #expect(item.state == .off)

        source.isSlideMode = true
        #expect(ViewerMenuValidator.validate(item, source: source))
        #expect(item.state == .on)
    }
}
