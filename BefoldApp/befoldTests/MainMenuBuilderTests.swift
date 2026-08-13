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

    /// AC#3: stable ビルド(ゲート OFF)では「変更されたファイルのみ表示」が View メニューに
    /// 出ない。実ビルドではゲートが片側に固定されるため、両分岐は注入点で検証する
    /// (ゲート越しの検証は動いているビルドの側しか通らない = 表示モードと同じ理由)。
    @Test("「変更されたファイルのみ表示」の露出はゲートの両方向で正しい", arguments: [true, false])
    func changedFilesOnlyExposureFollowsGateInBothDirections(isChangedFilesOnlyAvailable: Bool) throws {
        let view = try #require(
            MainMenuBuilder.makeViewMenuItem(
                isChangedFilesOnlyAvailable: isChangedFilesOnlyAvailable,
                isTreeLayoutAvailable: false
            ).submenu
        )

        let item = view.items.first { $0.action == #selector(AppDelegate.toggleChangedFilesOnly(_:)) }
        #expect((item != nil) == isChangedFilesOnlyAvailable)
        #expect(item?.keyEquivalent == (isChangedFilesOnlyAvailable ? "g" : nil))
        #expect(item?.keyEquivalentModifierMask == (isChangedFilesOnlyAvailable ? [.command, .control] : nil))
    }

    /// サイドバーのツリー表示も同じ形(ゲート値を引数で受ける)であることを両方向で確かめる。
    @Test("サイドバーのツリー表示の露出はゲートの両方向で正しい", arguments: [true, false])
    func sidebarTreeLayoutExposureFollowsGateInBothDirections(isTreeLayoutAvailable: Bool) {
        let menu = NSMenu()
        MainMenuBuilder.addSidebarItems(
            to: menu, isChangedFilesOnlyAvailable: false, isTreeLayoutAvailable: isTreeLayoutAvailable
        )

        let item = menu.items.first { $0.action == #selector(AppDelegate.toggleSidebarTreeLayout(_:)) }
        #expect((item != nil) == isTreeLayoutAvailable)
        // AC#1/#3: 露出するときは ⌃⌘T が付き、ゲート OFF では項目ごと(=ショートカットも)現れない。
        #expect(item?.keyEquivalent == (isTreeLayoutAvailable ? "t" : nil))
        #expect(item?.keyEquivalentModifierMask == (isTreeLayoutAvailable ? [.command, .control] : nil))
    }

    /// AC#2: View メニュー内でキー等価(キー + 修飾キー)が重複していない。
    /// ツリー表示に ⌃⌘T を足したことで既存の ⌃⌘H / ⌃⌘G / ⌃⌘F / ⌘S / ⌘[ / ⌘] と
    /// 衝突していないことを、個別比較ではなくメニュー全体の重複検査で担保する。
    @Test("View メニューのキー等価は重複しない", arguments: [true, false])
    func viewMenuShortcutsAreUnique(isGateAvailable: Bool) throws {
        let view = try #require(
            MainMenuBuilder.makeViewMenuItem(
                isChangedFilesOnlyAvailable: isGateAvailable,
                isTreeLayoutAvailable: isGateAvailable
            ).submenu
        )

        let shortcuts = view.items
            .filter { !$0.keyEquivalent.isEmpty }
            .map { "\($0.keyEquivalentModifierMask.rawValue):\($0.keyEquivalent)" }
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    /// 表示モードの選択(⌘1〜⌘3)とレイアウト切替(⌘\\)。差分は開発中機能なので、
    /// 露出はフィーチャーゲートと一致しなければならない(解除タスクは未起票)。
    @Test("View メニューの表示モード項目は ⌘1〜⌘3、差分とレイアウトはゲートと同じ有無になる")
    func viewMenuHasDisplayModeItems() throws {
        let view = try #require(fixture.submenu(titledKey: "menu.view.title"))

        let modeItems = view.items.filter { $0.action == #selector(ViewerWindowController.selectDisplayMode(_:)) }
        let expectedModes: [ViewerDisplayMode] = FeatureGate.isSourceDiffEnabled
            ? [.rendered, .source, .diff]
            : [.rendered, .source]
        #expect(modeItems.map(\.tag) == expectedModes.map(\.menuItemTag))
        for (item, mode) in zip(modeItems, expectedModes) {
            #expect(item.keyEquivalent == String(mode.menuItemTag))
            #expect(item.keyEquivalentModifierMask == [.command])
        }

        let layout = view.items.first { $0.action == #selector(ViewerWindowController.toggleDiffLayout(_:)) }
        #expect((layout != nil) == FeatureGate.isSourceDiffEnabled)
        if let layout {
            #expect(layout.keyEquivalent == "\\")
            #expect(layout.keyEquivalentModifierMask == [.command])
        }
    }

    /// AC#2: stable ビルド(ゲート OFF)では差分セグメントとレイアウト項目が現れない。
    /// 実ビルドではゲートが片側に固定されるため、両分岐は注入点で検証する
    /// (ゲート越しの検証は動いているビルドの側しか通らない = BookmarkShortcut と同じ理由)。
    @Test("表示モードの露出はフィーチャーゲートの両方向で正しい", arguments: [
        (isSourceDiffEnabled: true, modeCount: 3, hasLayout: true),
        (isSourceDiffEnabled: false, modeCount: 2, hasLayout: false),
    ])
    func displayModeExposureFollowsGateInBothDirections(
        isSourceDiffEnabled: Bool, modeCount: Int, hasLayout: Bool
    ) {
        // セグメント側(ツールバー)の並びと個数。
        let modes = ModeSegments.modes(isSourceDiffEnabled: isSourceDiffEnabled)
        #expect(modes.count == modeCount)
        #expect(modes.contains(.diff) == isSourceDiffEnabled)
        #expect(Array(modes.prefix(2)) == [.rendered, .source])

        // メニュー側。⌘1〜⌘3 とレイアウト(⌘\\)の有無が同じ判定に従う。
        let menu = NSMenu()
        MainMenuBuilder.addDisplayModeItems(to: menu, isSourceDiffEnabled: isSourceDiffEnabled)
        let modeItems = menu.items.filter { $0.action == #selector(ViewerWindowController.selectDisplayMode(_:)) }
        #expect(modeItems.map(\.keyEquivalent) == modes.map { String($0.menuItemTag) })
        let layout = menu.items.first { $0.action == #selector(ViewerWindowController.toggleDiffLayout(_:)) }
        #expect((layout != nil) == hasLayout)
        #expect(layout?.keyEquivalent == (hasLayout ? "\\" : nil))
    }

    /// 差分が ⌘3 へ移ったので ⌘D は空き、ブックマークはビルド種別によらず ⌘D に固定される。
    /// 以前は差分ゲートに応じて ⌘B / ⌘D を切り替えていたが、その分岐は撤去した(TASK-356)。
    @Test("ブックマークのキーはビルド種別によらず ⌘D")
    func viewMenuBookmarkAlwaysUsesCommandD() throws {
        let view = try #require(fixture.submenu(titledKey: "menu.view.title"))

        let item = try #require(view.items.first { $0.action == #selector(ViewerWindowController.toggleBookmark(_:)) })
        #expect(item.keyEquivalent == "d")
        #expect(item.keyEquivalentModifierMask == .command)
        #expect(BookmarkShortcut.keyEquivalent == "d")
        #expect(BookmarkShortcut.displayName == "⌘D")
        // ⌘D を持つ項目はちょうど 1 つ（ブックマークだけ）。
        let commandD = view.items.filter { $0.keyEquivalent == "d" && $0.keyEquivalentModifierMask == .command }
        #expect(commandD.count == 1)
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
