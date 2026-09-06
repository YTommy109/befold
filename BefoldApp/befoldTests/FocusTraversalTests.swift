import AppKit
@testable import befold
import BefoldKit
import SwiftUI
import Testing

/// サイドバーと本文のあいだのフォーカス移動（⌘← / ⌘→ / TASK-584）。
///
/// **Tab は使わない。** web 面では Tab / Shift+Tab がブラウザ既定の文書内リンク送りに
/// 使われており（`viewer-src/keyboard.ts` はどちらも見ていない）、奪うと Markdown 文書の
/// リンクをキーボードで辿れなくなる。矢印なら履歴（⌘[ / ⌘]）とも衝突せず、
/// PDF 面は Cmd 付きを `super` へ流し、web 面は `metaKey` で早期 return する。
@MainActor
@Suite
struct FocusTraversalTests {
    // MARK: - サイドバーのキー割り当て

    /// ⌘→ がサイドバーの「開く / 降りる」に食われないこと。修飾なしの `.rightArrow` は
    /// forward に割り当たっており、その switch は修飾キーを見ないので、明示的に譲る分岐が
    /// 無いと ⌘→ で**別のファイルが開いてしまう**。
    @Test("⌘→ はサイドバーのキー操作に食われない")
    func commandRightIsNotConsumedBySidebar() {
        let action = SidebarKeyAction.action(
            key: .rightArrow, modifiers: [.command],
            target: SidebarKeyAction.Target(kind: .file), mode: .tree
        )

        #expect(action == .ignored)
    }

    /// **⌘← は上位フォルダーへ移動しない（TASK-584 で廃止）。** 上へ出る手段は ⌘↑ と
    /// delete の 2 つで足りており、Finder も ⌘← を上位移動には使わない。ここが
    /// `.navigateToParent` に戻ると、本文からサイドバーへ戻る操作が奪われる。
    @Test("⌘← はサイドバーの上位フォルダー移動には使わない")
    func commandLeftNoLongerNavigatesToParent() {
        for mode in [SidebarLayoutMode.drillDown, .tree] {
            let action = SidebarKeyAction.action(
                key: .leftArrow, modifiers: [.command],
                target: SidebarKeyAction.Target(kind: .file), mode: mode
            )

            #expect(action == .ignored, "\(mode) で ⌘← が消費された")
        }
    }

    /// 上へ出る手段は残っていること。⌘← を外したせいでキーボードだけでルートより
    /// 上へ行けなくなっていないか。
    @Test("上位フォルダーへは ⌘↑ と delete で行ける")
    func parentNavigationRemainsReachable() {
        let target = SidebarKeyAction.Target(kind: .file)

        let commandUp = SidebarKeyAction.action(
            key: .upArrow, modifiers: [.command], target: target, mode: .drillDown
        )
        let deleteKey = SidebarKeyAction.action(
            key: .delete, modifiers: [], target: target, mode: .drillDown
        )

        #expect(commandUp == .navigateToParent)
        #expect(deleteKey == .navigateToParent)
    }

    /// 修飾なしの左右は従来どおり。⌘ の分岐を足したせいで素の矢印まで無効化していないか。
    @Test("修飾なしの左右は従来どおり働く")
    func plainArrowsKeepTheirMeaning() {
        let target = SidebarKeyAction.Target(kind: .file)

        let right = SidebarKeyAction.action(key: .rightArrow, modifiers: [], target: target, mode: .tree)
        let left = SidebarKeyAction.action(key: .leftArrow, modifiers: [], target: target, mode: .tree)

        #expect(right != .ignored)
        #expect(left != .ignored)
    }

    // MARK: - メニューの有効判定

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
        var effectiveDisplayMode = ViewerDisplayMode.rendered
        var isDiffLayoutSideBySide = false
        var isSidebarCollapsed = false
    }

    private func item(for selector: Selector) -> NSMenuItem {
        NSMenuItem(title: "", action: selector, keyEquivalent: "")
    }

    /// 畳んでいるときに ⌘← を通すと、行が 1 つも描かれていないサイドバーへフォーカスを
    /// 送ることになり、キー操作の宛先が消える。
    @Test("サイドバーを畳んでいると ⌘← は無効")
    func focusSidebarIsDisabledWhileCollapsed() {
        let source = StubSource()
        source.isSidebarCollapsed = true

        let enabled = ViewerMenuValidator.validate(
            item(for: #selector(ViewerWindowController.focusSidebar(_:))), source: source
        )

        #expect(!enabled)
    }

    @Test("サイドバーが出ていれば ⌘← は有効")
    func focusSidebarIsEnabledWhileVisible() {
        let source = StubSource()
        source.isSidebarCollapsed = false

        let enabled = ViewerMenuValidator.validate(
            item(for: #selector(ViewerWindowController.focusSidebar(_:))), source: source
        )

        #expect(enabled)
    }

    /// ⌘→ は能力で絞らない。どの種別でも「本文を読む」ことはできる。
    @Test("⌘→ はサイドバーの開閉によらず有効")
    func focusContentIsAlwaysEnabled() {
        let source = StubSource()
        source.isSidebarCollapsed = true

        let enabled = ViewerMenuValidator.validate(
            item(for: #selector(ViewerWindowController.focusContentSurface(_:))), source: source
        )

        #expect(enabled)
    }

    // MARK: - メニューに載っていること

    /// Help のショートカット一覧は `MenuShortcutCatalog` がメニューから収集するので、
    /// 項目がメニューに無ければ一覧にも出ない（AC #8）。
    @Test("表示メニューに 2 つの項目が ⌘← / ⌘→ で載っている")
    func viewMenuCarriesBothItems() throws {
        let menu = NSMenu()
        MainMenuBuilder.addFocusTraversalItems(to: menu)

        let sidebar = try #require(menu.items.first {
            $0.action == #selector(ViewerWindowController.focusSidebar(_:))
        })
        let content = try #require(menu.items.first {
            $0.action == #selector(ViewerWindowController.focusContentSurface(_:))
        })

        #expect(try sidebar.keyEquivalent == String(#require(UnicodeScalar(UInt16(NSLeftArrowFunctionKey)))))
        #expect(try content.keyEquivalent == String(#require(UnicodeScalar(UInt16(NSRightArrowFunctionKey)))))
        #expect(sidebar.keyEquivalentModifierMask == [.command])
        #expect(content.keyEquivalentModifierMask == [.command])
    }
}
