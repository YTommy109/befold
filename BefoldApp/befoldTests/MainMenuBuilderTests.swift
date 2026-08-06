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

    /// git 変更のみ表示は開発中機能(サイドバーの git ステータス)に依存するため、
    /// 露出はフィーチャーゲートと一致しなければならない(TASK-264、解除は TASK-187)。
    @Test("View メニューの「変更されたファイルのみ表示」はフィーチャーゲートと同じ有無になる")
    func viewMenuGatesChangedFilesOnlyItem() throws {
        let view = try #require(fixture.submenu(titledKey: "menu.view.title"))

        let item = view.items.first { $0.action == #selector(AppDelegate.toggleChangedFilesOnly(_:)) }
        #expect((item != nil) == FeatureGate.isSidebarGitStatusEnabled)
        if let item {
            #expect(item.keyEquivalent == "g")
            #expect(item.keyEquivalentModifierMask == [.command, .control])
        }
    }

    /// 差分表示はソース表示中に何度も切り替えるため、単独の ⌘D / ⇧⌘D を割り当てている
    /// (ブラウザ習慣の「⌘D = ブックマーク」より優先し、ブックマークは ⌘B へ移した)。
    /// 露出はフィーチャーゲートと一致しなければならない(解除タスクは未起票)。
    @Test("View メニューの差分項目はフィーチャーゲートと同じ有無で ⌘D / ⇧⌘D を持つ")
    func viewMenuGatesDiffItemsWithCommandD() throws {
        let view = try #require(fixture.submenu(titledKey: "menu.view.title"))

        let show = view.items.first { $0.action == #selector(ViewerWindowController.toggleSourceDiff(_:)) }
        let layout = view.items.first { $0.action == #selector(ViewerWindowController.toggleDiffLayout(_:)) }
        #expect((show != nil) == FeatureGate.isSourceDiffEnabled)
        #expect((layout != nil) == FeatureGate.isSourceDiffEnabled)
        if let show {
            #expect(show.keyEquivalent == "d")
            #expect(show.keyEquivalentModifierMask == [.command])
        }
        if let layout {
            #expect(layout.keyEquivalent == "d")
            #expect(layout.keyEquivalentModifierMask == [.command, .shift])
        }
    }

    /// ブックマークを ⌘B へ移す理由は「⌘D を差分表示へ譲る」ことだけなので、差分項目が
    /// 出ないビルド（stable）では ⌘D のままでなければならない。無条件に ⌘B へ移すと、
    /// stable では ⌘D が誰にも割り当たらないままブックマークだけが黙って動く（TASK-333）。
    @Test("ブックマークのキーはフィーチャーゲートに合わせて ⌘D / ⌘B を切り替える")
    func viewMenuBookmarkKeyFollowsDiffGate() throws {
        let view = try #require(fixture.submenu(titledKey: "menu.view.title"))

        let item = try #require(view.items.first { $0.action == #selector(ViewerWindowController.toggleBookmark(_:)) })
        #expect(item.keyEquivalent == BookmarkShortcut.keyEquivalent)
        #expect(item.keyEquivalentModifierMask == .command)
        // ⌘D を持つ項目はビルドを通じて常にちょうど 1 つ（差分表示 or ブックマーク）。
        let commandD = view.items.filter { $0.keyEquivalent == "d" && $0.keyEquivalentModifierMask == .command }
        #expect(commandD.count == 1)
    }

    /// 実ビルドではゲートが片側に固定されるため、両分岐は純粋判定で押さえる。
    @Test("差分を露出しないビルドではブックマークが ⌘D のまま", arguments: [
        (isSourceDiffEnabled: true, key: "b", display: "⌘B"),
        (isSourceDiffEnabled: false, key: "d", display: "⌘D"),
    ])
    func bookmarkShortcutFollowsGateInBothDirections(
        isSourceDiffEnabled: Bool, key: String, display: String
    ) {
        #expect(BookmarkShortcut.keyEquivalent(isSourceDiffEnabled: isSourceDiffEnabled) == key)
        #expect(BookmarkShortcut.displayName(isSourceDiffEnabled: isSourceDiffEnabled) == display)
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
