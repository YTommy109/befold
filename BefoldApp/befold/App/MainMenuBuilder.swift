import AppKit

/// Help メニュー配下の各項目のアクション。パラメータ数を抑えるために 1 つにまとめる。
struct MainMenuHelpActions {
    let visitWebsite: Selector
    let featureOverview: Selector
    let keyboardShortcuts: Selector
    let aiIntegration: Selector
    let ossAcknowledgements: Selector
}

@MainActor
enum MainMenuBuilder {
    static func build(
        openAction: Selector,
        helpActions: MainMenuHelpActions,
        recentMenuDelegate: NSMenuDelegate,
        bookmarksMenuDelegate: NSMenuDelegate,
        recentRepositoriesMenuDelegate: NSMenuDelegate
    ) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeFileMenuItem(
            openAction: openAction,
            recentMenuDelegate: recentMenuDelegate,
            bookmarksMenuDelegate: bookmarksMenuDelegate,
            recentRepositoriesMenuDelegate: recentRepositoriesMenuDelegate
        ))
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeViewMenuItem())
        mainMenu.addItem(makeWindowMenuItem())
        mainMenu.addItem(makeHelpMenuItem(helpActions))
        return mainMenu
    }

    private static func makeAppMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()
        item.submenu = menu
        menu.addLocalizedItem("menu.app.about", action: #selector(AppDelegate.showAbout(_:)))
        // 設定は macOS 標準どおり About の直後(⌘,)に置く。
        menu.addItem(.separator())
        menu.addLocalizedItem(
            "menu.app.settings",
            action: #selector(AppDelegate.showSettings(_:)),
            keyEquivalent: ",",
            modifiers: [.command]
        )
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.app.checkForUpdates", action: #selector(AppDelegate.checkForUpdates(_:)))
        menu.addLocalizedItem("menu.app.installCLI", action: #selector(AppDelegate.installCLI(_:)))
        menu.addItem(.separator())
        let servicesTitle = String(localized: "menu.app.services", bundle: .l10n)
        let servicesItem = NSMenuItem(title: servicesTitle, action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu(title: servicesTitle)
        NSApp.servicesMenu = servicesItem.submenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.app.hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addLocalizedItem(
            "menu.app.hideOthers",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        )
        menu.addLocalizedItem("menu.app.showAll", action: #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.app.quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item
    }

    private static func makeFileMenuItem(
        openAction: Selector, recentMenuDelegate: NSMenuDelegate, bookmarksMenuDelegate: NSMenuDelegate,
        recentRepositoriesMenuDelegate: NSMenuDelegate
    ) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.file.title", bundle: .l10n))
        item.submenu = menu
        menu.addLocalizedItem("menu.file.open", action: openAction, keyEquivalent: "o")
        menu.addLocalizedItem(
            "menu.file.quickOpen",
            action: #selector(AppDelegate.showQuickOpen(_:)),
            keyEquivalent: "p"
        )

        // 「開くコマンド」と「記憶済みリストから選ぶ」を区切る。
        // リストは履歴(Open Recent / Recent Repositories)を隣接させ、手動登録の Bookmarks を末尾に置く。
        menu.addItem(.separator())

        menu.addLocalizedSubmenu("menu.file.openRecent", delegate: recentMenuDelegate)
        menu.addLocalizedSubmenu("menu.file.recentRepositories", delegate: recentRepositoriesMenuDelegate)
        menu.addLocalizedSubmenu("menu.file.bookmarks", delegate: bookmarksMenuDelegate)

        menu.addItem(.separator())
        menu.addLocalizedItem("menu.file.close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(.separator())
        // ⌘P は Quick Open に譲り、Print は ⇧⌘P へ移す。
        // 小文字 + shift マスクで統一する(同ファイルの redo / findPrevious / hideOthers と同方式)。
        menu.addLocalizedItem(
            "menu.file.print",
            action: #selector(ViewerWindowController.printDocument(_:)),
            keyEquivalent: "p",
            modifiers: [.command, .shift]
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
        menu.addLocalizedItem("menu.edit.undo", action: Selector(("undo:")), keyEquivalent: "z")
        // redo は macOS 標準どおり undo と同じキー(z)に shift を重ねて区別する。
        menu.addLocalizedItem(
            "menu.edit.redo",
            action: Selector(("redo:")),
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        )
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.edit.cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addLocalizedItem("menu.edit.copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addLocalizedItem("menu.edit.paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addLocalizedItem("menu.edit.delete", action: #selector(NSText.delete(_:)))
        menu.addLocalizedItem("menu.edit.selectAll", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.edit.find", action: #selector(ViewerWindowController.find(_:)), keyEquivalent: "f")
        menu.addLocalizedItem(
            "menu.edit.findNext",
            action: #selector(ViewerWindowController.findNext(_:)),
            keyEquivalent: "g"
        )
        // findNext と同じキー(g)に shift を重ねて逆方向を表す(Safari 等と同じ慣習)。
        menu.addLocalizedItem(
            "menu.edit.findPrevious",
            action: #selector(ViewerWindowController.findPrevious(_:)),
            keyEquivalent: "g",
            modifiers: [.command, .shift]
        )
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
        menu.addItem(.separator())
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
        addDiffItems(to: menu)
        // ⌘D はブラウザ習慣ではブックマークだが、このアプリでは差分表示のほうが
        // 圧倒的に高頻度なので差分へ譲り、ブックマークは ⌘B へ移した。ただし差分項目は
        // フィーチャーゲートの内側にしか無いため、譲るかどうかは BookmarkShortcut が決める。
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
        menu.addItem(.separator())
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
        menu.addItem(.separator())
        // 素の ⌘H は App メニューの Hide(NSApplication.hide)と衝突するため、
        // control を重ねて区別する。
        menu.addLocalizedItem(
            "menu.view.showHiddenFiles",
            action: #selector(AppDelegate.toggleHiddenFiles(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .control]
        )
        // 開発中機能(サイドバーの git ステータス)に依存するため、露出点でゲートする。
        // 素の ⌘G / ⇧⌘G は Edit メニューの検索送りと衝突するため、control を重ねて区別する。
        if FeatureGate.isSidebarGitStatusEnabled {
            menu.addLocalizedItem(
                "menu.view.showChangedFilesOnly",
                action: #selector(AppDelegate.toggleChangedFilesOnly(_:)),
                keyEquivalent: "g",
                modifiers: [.command, .control]
            )
        }
        // macOS 標準のフルスクリーン切替ショートカット(⌃⌘F)に合わせる。
        menu.addLocalizedItem(
            "menu.view.enterFullScreen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f",
            modifiers: [.control, .command]
        )
        return item
    }

    private static func makeWindowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.window.title", bundle: .l10n))
        item.submenu = menu
        menu.addLocalizedItem(
            "menu.window.minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addLocalizedItem("menu.window.zoom", action: #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.window.showPreviousTab", action: #selector(NSWindow.selectPreviousTab(_:)))
        menu.addLocalizedItem("menu.window.showNextTab", action: #selector(NSWindow.selectNextTab(_:)))
        menu.addLocalizedItem("menu.window.moveTabToNewWindow", action: #selector(NSWindow.moveTabToNewWindow(_:)))
        menu.addLocalizedItem("menu.window.mergeAllWindows", action: #selector(NSWindow.mergeAllWindows(_:)))
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.window.bringAllToFront", action: #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = menu
        return item
    }

    private static func makeHelpMenuItem(_ actions: MainMenuHelpActions) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.help.title", bundle: .l10n))
        item.submenu = menu
        menu.addLocalizedItem("menu.help.featureOverview", action: actions.featureOverview)
        menu.addLocalizedItem("menu.help.keyboardShortcuts", action: actions.keyboardShortcuts)
        menu.addLocalizedItem("menu.help.aiIntegration", action: actions.aiIntegration)
        menu.addItem(.separator())
        menu.addLocalizedItem("menu.help.visitWebsite", action: actions.visitWebsite, keyEquivalent: "?")
        menu.addLocalizedItem("menu.help.ossAcknowledgements", action: actions.ossAcknowledgements)
        NSApp.helpMenu = menu
        return item
    }

    /// ソース表示の git 差分に関する項目。フィーチャーゲートが無効なビルドでは足さない。
    private static func addDiffItems(to menu: NSMenu) {
        guard FeatureGate.isSourceDiffEnabled else { return }
        menu.addLocalizedItem(
            "menu.view.showDiff",
            action: #selector(ViewerWindowController.toggleSourceDiff(_:)),
            keyEquivalent: "d",
            modifiers: [.command]
        )
        menu.addLocalizedItem(
            "menu.view.diffSideBySide",
            action: #selector(ViewerWindowController.toggleDiffLayout(_:)),
            keyEquivalent: "d",
            modifiers: [.command, .shift]
        )
    }
}
