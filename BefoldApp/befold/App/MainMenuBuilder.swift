import AppKit

@MainActor
enum MainMenuBuilder {
    static func build(
        openAction: Selector,
        helpAction: Selector,
        recentMenuDelegate: NSMenuDelegate
    ) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeFileMenuItem(openAction: openAction, recentMenuDelegate: recentMenuDelegate))
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeViewMenuItem())
        mainMenu.addItem(makeWindowMenuItem())
        mainMenu.addItem(makeHelpMenuItem(helpAction: helpAction))
        return mainMenu
    }

    private static func makeAppMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()
        item.submenu = menu
        menu.addItem(
            withTitle: String(localized: "menu.app.about", bundle: .l10n),
            action: #selector(AppDelegate.showAbout(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.app.checkForUpdates", bundle: .l10n),
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.app.installCLI", bundle: .l10n),
            action: #selector(AppDelegate.installCLI(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        let servicesTitle = String(localized: "menu.app.services", bundle: .l10n)
        let servicesItem = NSMenuItem(title: servicesTitle, action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu(title: servicesTitle)
        NSApp.servicesMenu = servicesItem.submenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.app.hide", bundle: .l10n),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = menu.addItem(
            withTitle: String(localized: "menu.app.hideOthers", bundle: .l10n),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: String(localized: "menu.app.showAll", bundle: .l10n),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.app.quit", bundle: .l10n),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return item
    }

    private static func makeFileMenuItem(openAction: Selector, recentMenuDelegate: NSMenuDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.file.title", bundle: .l10n))
        item.submenu = menu
        menu.addItem(
            withTitle: String(localized: "menu.file.open", bundle: .l10n),
            action: openAction,
            keyEquivalent: "o"
        )

        let recentTitle = String(localized: "menu.file.openRecent", bundle: .l10n)
        let recentItem = NSMenuItem(title: recentTitle, action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: recentTitle)
        recentMenu.delegate = recentMenuDelegate
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.file.close", bundle: .l10n),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.file.print", bundle: .l10n),
            action: #selector(ViewerWindowController.printDocument(_:)),
            keyEquivalent: "p"
        )
        return item
    }

    /// ビューア専用アプリだが、⌘C コピー・⌘A 全選択などのキーイベントは
    /// 対応するメニュー項目が存在して初めてファーストレスポンダ（WKWebView）へ
    /// 配送されるため、標準構成の Edit メニューを用意する。
    /// undo/redo・cut/copy/paste/delete/selectAll は NSResponder の標準セレクタに
    /// そのまま委譲し、Find 系だけ WKWebView 内蔵の検索バーを操作する
    /// ViewerWindowController のアクションへつなぐ(標準の Find パネルは使わない)。
    private static func makeEditMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.edit.title", bundle: .l10n))
        item.submenu = menu
        // undo:/redo: は NSUndoManager が実装時のみ応答するセレクタで #selector による
        // コンパイル時チェック対象の宣言が存在しないため、文字列セレクタで指定する。
        menu.addItem(
            withTitle: String(localized: "menu.edit.undo", bundle: .l10n),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redo = menu.addItem(
            withTitle: String(localized: "menu.edit.redo", bundle: .l10n),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        // redo は macOS 標準どおり undo と同じキー(z)に shift を重ねて区別する。
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.edit.cut", bundle: .l10n),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        menu.addItem(
            withTitle: String(localized: "menu.edit.copy", bundle: .l10n),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        menu.addItem(
            withTitle: String(localized: "menu.edit.paste", bundle: .l10n),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        menu.addItem(
            withTitle: String(localized: "menu.edit.delete", bundle: .l10n),
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.edit.selectAll", bundle: .l10n),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.edit.find", bundle: .l10n),
            action: #selector(ViewerWindowController.find(_:)),
            keyEquivalent: "f"
        )
        menu.addItem(
            withTitle: String(localized: "menu.edit.findNext", bundle: .l10n),
            action: #selector(ViewerWindowController.findNext(_:)),
            keyEquivalent: "g"
        )
        let findPrevious = menu.addItem(
            withTitle: String(localized: "menu.edit.findPrevious", bundle: .l10n),
            action: #selector(ViewerWindowController.findPrevious(_:)),
            keyEquivalent: "g"
        )
        // findNext と同じキー(g)に shift を重ねて逆方向を表す(Safari 等と同じ慣習)。
        findPrevious.keyEquivalentModifierMask = [.command, .shift]
        return item
    }

    /// ズーム・表示モード切替・サイドバー・履歴ナビゲーションをまとめた View メニュー。
    /// 大半は ViewerWindowController のアクションへ委譲する薄いラッパーだが、
    /// 一部の項目は他メニューとのキーバインド衝突を避けるため既定の修飾キーを
    /// 上書きしている(各項目の直前コメント参照)。
    private static func makeViewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.view.title", bundle: .l10n))
        item.submenu = menu
        menu.addItem(
            withTitle: String(localized: "menu.view.actualSize", bundle: .l10n),
            action: #selector(ViewerWindowController.resetZoom(_:)),
            keyEquivalent: "0"
        )
        menu.addItem(
            withTitle: String(localized: "menu.view.zoomIn", bundle: .l10n),
            action: #selector(ViewerWindowController.zoomIn(_:)),
            keyEquivalent: "+"
        )
        menu.addItem(
            withTitle: String(localized: "menu.view.zoomOut", bundle: .l10n),
            action: #selector(ViewerWindowController.zoomOut(_:)),
            keyEquivalent: "-"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.view.toggleSource", bundle: .l10n),
            action: #selector(ViewerWindowController.toggleSourceView(_:)),
            keyEquivalent: "u"
        )
        menu.addItem(
            withTitle: String(localized: "menu.view.showLineNumbers", bundle: .l10n),
            action: #selector(ViewerWindowController.toggleLineNumbers(_:)),
            keyEquivalent: "l"
        )
        menu.addItem(
            withTitle: String(localized: "menu.view.addBookmark", bundle: .l10n),
            action: #selector(ViewerWindowController.toggleBookmark(_:)),
            keyEquivalent: "d"
        )
        menu.addItem(.separator())
        let toggleSidebar = menu.addItem(
            withTitle: String(localized: "menu.view.toggleSidebar", bundle: .l10n),
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s"
        )
        // addItem(withTitle:...) の既定修飾キーは [.command] だが、意図を明示するため
        // 明示的に上書きしている(挙動は変わらない)。
        toggleSidebar.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.view.goBack", bundle: .l10n),
            action: #selector(ViewerWindowController.goBack(_:)),
            keyEquivalent: "["
        )
        menu.addItem(
            withTitle: String(localized: "menu.view.goForward", bundle: .l10n),
            action: #selector(ViewerWindowController.goForward(_:)),
            keyEquivalent: "]"
        )
        menu.addItem(.separator())
        let toggleHiddenFiles = menu.addItem(
            withTitle: String(localized: "menu.view.showHiddenFiles", bundle: .l10n),
            action: #selector(AppDelegate.toggleHiddenFiles(_:)),
            keyEquivalent: "h"
        )
        // 素の ⌘H は App メニューの Hide(NSApplication.hide)と衝突するため、
        // control を重ねて区別する。
        toggleHiddenFiles.keyEquivalentModifierMask = [.command, .control]
        let fullScreen = menu.addItem(
            withTitle: String(localized: "menu.view.enterFullScreen", bundle: .l10n),
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        // macOS 標準のフルスクリーン切替ショートカット(⌃⌘F)に合わせる。
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        return item
    }

    private static func makeWindowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.window.title", bundle: .l10n))
        item.submenu = menu
        menu.addItem(
            withTitle: String(localized: "menu.window.minimize", bundle: .l10n),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(
            withTitle: String(localized: "menu.window.zoom", bundle: .l10n),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.window.showPreviousTab", bundle: .l10n),
            action: #selector(NSWindow.selectPreviousTab(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.window.showNextTab", bundle: .l10n),
            action: #selector(NSWindow.selectNextTab(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.window.moveTabToNewWindow", bundle: .l10n),
            action: #selector(NSWindow.moveTabToNewWindow(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.window.mergeAllWindows", bundle: .l10n),
            action: #selector(NSWindow.mergeAllWindows(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.window.bringAllToFront", bundle: .l10n),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = menu
        return item
    }

    private static func makeHelpMenuItem(helpAction: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.help.title", bundle: .l10n))
        item.submenu = menu
        menu.addItem(
            withTitle: String(localized: "menu.help.appHelp", bundle: .l10n),
            action: helpAction,
            keyEquivalent: "?"
        )
        NSApp.helpMenu = menu
        return item
    }
}
