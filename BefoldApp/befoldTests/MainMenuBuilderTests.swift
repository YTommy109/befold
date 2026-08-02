import AppKit
@testable import befold
import Testing

@Suite
@MainActor
struct MainMenuBuilderTests {
    private let fixture = MainMenuFixture()

    @Test("トップレベルは App/File/Edit/View/Window/Help の 6 メニュー")
    func topLevelMenusArePresent() {
        let mainMenu = fixture.menu()

        #expect(mainMenu.items.count == 6)
        let titles = mainMenu.items.compactMap(\.submenu?.title)
        #expect(titles.contains(fixture.localizedTitle("menu.file.title")))
        #expect(titles.contains(fixture.localizedTitle("menu.edit.title")))
        #expect(titles.contains(fixture.localizedTitle("menu.view.title")))
        #expect(titles.contains(fixture.localizedTitle("menu.window.title")))
        #expect(titles.contains(fixture.localizedTitle("menu.help.title")))
    }

    @Test("File メニューの記憶済みリストは 履歴2つ → Bookmarks の順で並ぶ")
    func fileMenuListsHistoriesBeforeBookmarks() throws {
        let file = try #require(fixture.submenu(titledKey: "menu.file.title"))

        let recentIndex = try #require(file.items.firstIndex {
            $0.submenu?.title == fixture.localizedTitle("menu.file.openRecent")
        })
        let recentRepositoriesIndex = try #require(file.items.firstIndex {
            $0.submenu?.title == fixture.localizedTitle("menu.file.recentRepositories")
        })
        let bookmarksIndex = try #require(file.items.firstIndex {
            $0.submenu?.title == fixture.localizedTitle("menu.file.bookmarks")
        })
        #expect(recentRepositoriesIndex == recentIndex + 1)
        #expect(bookmarksIndex == recentRepositoriesIndex + 1)
        // 「開くコマンド」群とは区切り線で分かれ、リスト群の直後も区切り線で閉じる。
        #expect(file.items[recentIndex - 1].isSeparatorItem)
        #expect(file.items[bookmarksIndex + 1].isSeparatorItem)
    }

    @Test("File メニューに Recent Repositories サブメニューがある")
    func fileMenuHasRecentRepositoriesSubmenu() throws {
        // NSMenu.delegate は weak のため、フィクスチャに強参照を持たせて識別する
        // (build() 呼び出し中だけの参照だと、代入直後に解放されて nil になる)。
        let delegate = MainMenuFixture.StubMenuDelegate()
        let injectedFixture = MainMenuFixture(recentRepositoriesMenuDelegate: delegate)
        let file = try #require(injectedFixture.submenu(titledKey: "menu.file.title"))

        let recentRepositoriesItem = try #require(file.items.first {
            $0.submenu?.title == injectedFixture.localizedTitle("menu.file.recentRepositories")
        })
        #expect(recentRepositoriesItem.submenu?.delegate === delegate)
    }

    @Test("Edit メニューに Copy(⌘C) と Select All(⌘A) がある")
    func editMenuEnablesCopyAndSelectAll() throws {
        let edit = try #require(fixture.submenu(titledKey: "menu.edit.title"))

        let copy = try #require(edit.items.first { $0.action == #selector(NSText.copy(_:)) })
        #expect(copy.keyEquivalent == "c")
        let selectAll = try #require(edit.items.first { $0.action == #selector(NSText.selectAll(_:)) })
        #expect(selectAll.keyEquivalent == "a")
    }

    @Test("View メニューにズームとフルスクリーンがある")
    func viewMenuHasZoomAndFullScreen() throws {
        let view = try #require(fixture.submenu(titledKey: "menu.view.title"))

        #expect(view.items.contains { $0.action == #selector(ViewerWindowController.zoomIn(_:)) })
        #expect(view.items.contains { $0.action == #selector(ViewerWindowController.zoomOut(_:)) })
        #expect(view.items.contains { $0.action == #selector(ViewerWindowController.resetZoom(_:)) })
        let fullScreen = try #require(
            view.items.first { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
        )
        #expect(fullScreen.keyEquivalentModifierMask == [.control, .command])
    }

    /// メニュー項目が期待するセレクタ・ショートカットキー・修飾キーを持つこと。
    /// modifiers が nil のケース(Print)は元テストどおり修飾キーを検証しない。
    @Test(arguments: [
        (
            submenuKey: "menu.view.title",
            selector: #selector(NSSplitViewController.toggleSidebar(_:)),
            key: "s", modifiers: NSEvent.ModifierFlags?.some([.command])
        ), // View メニューに Toggle Sidebar(⌘S) がある
        (
            submenuKey: "menu.view.title",
            selector: #selector(ViewerWindowController.goBack(_:)),
            key: "[", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // View メニューに Back(⌘[) がある
        (
            submenuKey: "menu.view.title",
            selector: #selector(ViewerWindowController.goForward(_:)),
            key: "]", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // View メニューに Forward(⌘]) がある
        (
            submenuKey: "menu.view.title",
            selector: #selector(ViewerWindowController.toggleLineNumbers(_:)),
            key: "l", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // View メニューに Toggle Line Numbers(⌘L) がある
        (
            submenuKey: "menu.view.title",
            selector: #selector(AppDelegate.toggleHiddenFiles(_:)),
            key: "h", modifiers: NSEvent.ModifierFlags?.some([.command, .control])
        ), // View メニューに Show Hidden Files(⌘⌃H) がある
        (
            submenuKey: "menu.view.title",
            selector: #selector(ViewerWindowController.toggleBookmark(_:)),
            key: "d", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // View メニューに Bookmark(⌘D) がある
        (
            submenuKey: "menu.file.title",
            selector: #selector(AppDelegate.showQuickOpen(_:)),
            key: "p", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // File メニューに Quick Open(⌘P) がある
        (
            submenuKey: "menu.file.title",
            selector: #selector(ViewerWindowController.printDocument(_:)),
            key: "p", modifiers: NSEvent.ModifierFlags?.some([.command, .shift])
        ), // Quick Open に ⌘P を譲り、Print は ⇧⌘P へ移した
    ])
    func menuItemHasKeyEquivalent(
        submenuKey: String, selector: Selector, key: String, modifiers: NSEvent.ModifierFlags?
    ) throws {
        let menu = try #require(fixture.submenu(titledKey: String.LocalizationValue(submenuKey)))

        let item = try #require(menu.items.first { $0.action == selector })
        #expect(item.keyEquivalent == key)
        if let modifiers {
            #expect(item.keyEquivalentModifierMask == modifiers)
        }
    }

    @Test("Window メニューにタブ操作項目がある")
    func windowMenuHasTabItems() throws {
        let window = try #require(fixture.submenu(titledKey: "menu.window.title"))

        #expect(window.items.contains { $0.action == #selector(NSWindow.selectNextTab(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.selectPreviousTab(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.moveTabToNewWindow(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.mergeAllWindows(_:)) })
    }

    @Test("Help メニューが NSApp.helpMenu に登録される")
    func helpMenuIsRegistered() throws {
        let help = try #require(fixture.submenu(titledKey: "menu.help.title"))

        #expect(NSApp.helpMenu === help)
        #expect(help.items.contains { $0.action == #selector(AppDelegate.openHelp(_:)) })
    }

    /// 設定は dev 限定のフィーチャーゲートを外して stable でも常に出す(TASK-184)。
    @Test("App メニューに Settings…(⌘,) 項目がビルド種別に関わらずある")
    func appMenuHasSettingsItem() throws {
        let mainMenu = fixture.menu()
        let appMenu = try #require(mainMenu.items.first?.submenu)

        let settings = try #require(
            appMenu.items.first { $0.action == #selector(AppDelegate.showSettings(_:)) }
        )
        #expect(settings.title == fixture.localizedTitle("menu.app.settings"))
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == [.command])
    }

    @Test("App メニューに Install CLI 項目がある")
    func appMenuHasInstallCLIItem() throws {
        let mainMenu = fixture.menu()
        let appMenu = try #require(mainMenu.items.first?.submenu)

        let installItem = try #require(
            appMenu.items.first { $0.action == #selector(AppDelegate.installCLI(_:)) }
        )
        #expect(installItem.title == fixture.localizedTitle("menu.app.installCLI"))
    }
}
