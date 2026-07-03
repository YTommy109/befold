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
            withTitle: "About mmdview",
            action: #selector(AppDelegate.showAbout(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesItem.submenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Hide mmdview",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit mmdview",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return item
    }

    private static func makeFileMenuItem(openAction: Selector, recentMenuDelegate: NSMenuDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        item.submenu = menu
        menu.addItem(
            withTitle: "Open…",
            action: openAction,
            keyEquivalent: "o"
        )

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = recentMenuDelegate
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Print…",
            action: #selector(ViewerWindowController.printDocument(_:)),
            keyEquivalent: "p"
        )
        return item
    }

    /// ビューア専用アプリだが、⌘C コピー・⌘A 全選択などのキーイベントは
    /// 対応するメニュー項目が存在して初めてファーストレスポンダ（WKWebView）へ
    /// 配送されるため、標準構成の Edit メニューを用意する。
    private static func makeEditMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        item.submenu = menu
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return item
    }

    private static func makeViewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")
        item.submenu = menu
        menu.addItem(
            withTitle: "Actual Size",
            action: #selector(ViewerWindowController.resetZoom(_:)),
            keyEquivalent: "0"
        )
        menu.addItem(
            withTitle: "Zoom In",
            action: #selector(ViewerWindowController.zoomIn(_:)),
            keyEquivalent: "+"
        )
        menu.addItem(
            withTitle: "Zoom Out",
            action: #selector(ViewerWindowController.zoomOut(_:)),
            keyEquivalent: "-"
        )
        menu.addItem(.separator())
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        return item
    }

    private static func makeWindowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")
        item.submenu = menu
        menu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Show Previous Tab",
            action: #selector(NSWindow.selectPreviousTab(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Show Next Tab",
            action: #selector(NSWindow.selectNextTab(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Move Tab to New Window",
            action: #selector(NSWindow.moveTabToNewWindow(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Merge All Windows",
            action: #selector(NSWindow.mergeAllWindows(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = menu
        return item
    }

    private static func makeHelpMenuItem(helpAction: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")
        item.submenu = menu
        menu.addItem(
            withTitle: "mmdview Help",
            action: helpAction,
            keyEquivalent: "?"
        )
        NSApp.helpMenu = menu
        return item
    }
}
