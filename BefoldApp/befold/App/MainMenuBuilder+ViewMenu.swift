import AppKit

/// View メニューの構築。MainMenuBuilder 本体から分けているのは、swiftlint の
/// type_body_length を超えないようにするため(他のメニュー構築と同じ粒度で切り出す)。
///
/// キー等価の定義は紹介サイトのショートカット表と突き合わせている。読み手は
/// `MainMenuBuilder*.swift` を全件見る形にしてあるので(site/vitest.config.ts と
/// .github/workflows/site.yml の paths)、さらに分割するときもこの命名を保つこと。
extension MainMenuBuilder {
    static func makeViewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.view.title", bundle: .l10n))
        item.submenu = menu
        addZoomItems(to: menu)
        menu.addItem(.separator())
        addDisplayModeItems(to: menu)
        menu.addLocalizedItem(
            "menu.view.toggleSource",
            action: #selector(ViewerWindowController.toggleSourceView(_:)),
            keyEquivalent: "u"
        )
        menu.addLocalizedItem(
            "menu.view.showLineNumbers",
            action: #selector(ViewerWindowController.toggleLineNumbers(_:)),
            keyEquivalent: "l"
        )
        menu.addLocalizedItem(
            "menu.view.addBookmark",
            action: #selector(ViewerWindowController.toggleBookmark(_:)),
            keyEquivalent: BookmarkShortcut.keyEquivalent
        )
        menu.addItem(.separator())
        // キー等価を与えたときの既定修飾キーは [.command] だが、意図を明示するため
        // 明示的に指定している(挙動は変わらない)。
        menu.addLocalizedItem(
            "menu.view.toggleSidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s",
            modifiers: [.command]
        )
        addFocusTraversalItems(to: menu)
        menu.addItem(.separator())
        addHistoryItems(to: menu)
        menu.addItem(.separator())
        addSidebarItems(to: menu)
        // macOS 標準のフルスクリーン切替ショートカット(⌃⌘F)に合わせる。
        menu.addLocalizedItem(
            "menu.view.enterFullScreen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f",
            modifiers: [.control, .command]
        )
        return item
    }

    /// サイドバーのツリー表示の切替項目。
    /// ⌘1〜4 はプレビューの表示モードに割り当て済み(TASK-356)なので、他のサイドバー項目
    /// (⌃⌘H / ⌃⌘G)と同じ ⌃⌘ 系に揃えて ⌃⌘T を割り当てる(TASK-409)。素の ⌘T は
    /// ウインドウのタブ操作を連想させるため control を重ねて区別する。
    static func addSidebarTreeLayoutItem(to menu: NSMenu) {
        menu.addLocalizedItem(
            "menu.view.sidebarTreeLayout",
            action: #selector(AppDelegate.toggleSidebarTreeLayout(_:)),
            keyEquivalent: "t",
            modifiers: [.command, .control]
        )
    }

    /// サイドバーの「変更されたファイルのみ表示」切替項目。
    /// 素の ⌘G / ⇧⌘G は Edit メニューの検索送りと衝突するため、control を重ねて区別する。
    static func addChangedFilesOnlyItem(to menu: NSMenu) {
        menu.addLocalizedItem(
            "menu.view.showChangedFilesOnly",
            action: #selector(AppDelegate.toggleChangedFilesOnly(_:)),
            keyEquivalent: "g",
            modifiers: [.command, .control]
        )
    }

    /// View メニューのサイドバー関連項目(不可視ファイル・変更のみ表示・ツリー表示)。
    /// makeViewMenuItem から切り出しているのは、1 関数が長くなりすぎないようにするため。
    static func addSidebarItems(to menu: NSMenu) {
        // 素の ⌘H は App メニューの Hide(NSApplication.hide)と衝突するため、
        // control を重ねて区別する。
        menu.addLocalizedItem(
            "menu.view.showHiddenFiles",
            action: #selector(AppDelegate.toggleHiddenFiles(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .control]
        )
        addChangedFilesOnlyItem(to: menu)
        addSidebarTreeLayoutItem(to: menu)
    }

    /// ファイル履歴の前後移動(⌘[ / ⌘])。makeViewMenuItem から切り出しているのは、
    /// 1 関数が長くなりすぎないようにするため。
    static func addHistoryItems(to menu: NSMenu) {
        menu.addLocalizedItem(
            "menu.view.goBack",
            action: #selector(ViewerWindowController.goBack(_:)),
            keyEquivalent: "["
        )
        menu.addLocalizedItem(
            "menu.view.goForward",
            action: #selector(ViewerWindowController.goForward(_:)),
            keyEquivalent: "]"
        )
    }

    /// サイドバーと本文のあいだでキーボードのフォーカスを移す項目（TASK-584）。
    ///
    /// **Tab ではなく ⌘← / ⌘→ にしてある。** web 面では Tab / Shift+Tab がブラウザ既定の
    /// 文書内リンク送りに使われており（`viewer-src/keyboard.ts` はどちらも見ていない）、
    /// 奪うと Markdown 文書のリンクをキーボードで辿れなくなる。矢印は履歴（⌘[ / ⌘]）とも
    /// 衝突せず、PDF 面は Cmd 付きを `super` へ流し、web 面は `metaKey` で早期 return する。
    static func addFocusTraversalItems(to menu: NSMenu) {
        menu.addLocalizedItem(
            "menu.view.focusSidebar",
            action: #selector(ViewerWindowController.focusSidebar(_:)),
            keyEquivalent: String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!)
        )
        menu.addLocalizedItem(
            "menu.view.focusContent",
            action: #selector(ViewerWindowController.focusContentSurface(_:)),
            keyEquivalent: String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!)
        )
    }

    /// 表示倍率の項目(実寸・拡大・縮小)。makeViewMenuItem から切り出しているのは、
    /// 1 関数が長くなりすぎないようにするため。
    static func addZoomItems(to menu: NSMenu) {
        menu.addLocalizedItem(
            "menu.view.actualSize",
            action: #selector(ViewerWindowController.resetZoom(_:)),
            keyEquivalent: "0"
        )
        menu.addLocalizedItem(
            "menu.view.zoomIn",
            action: #selector(ViewerWindowController.zoomIn(_:)),
            keyEquivalent: "+"
        )
        menu.addLocalizedItem(
            "menu.view.zoomOut",
            action: #selector(ViewerWindowController.zoomOut(_:)),
            keyEquivalent: "-"
        )
    }
}
