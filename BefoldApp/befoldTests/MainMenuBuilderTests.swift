import AppKit
@testable import befold
import Testing

@Suite
@MainActor
struct MainMenuBuilderTests {
    private final class StubMenuDelegate: NSObject, NSMenuDelegate {}

    // NSMenu.delegate は weak。buildMenu() 呼び出し中だけの一時インスタンスだと、
    // 代入直後に解放されて delegate が nil に化ける(トラップ)。struct のプロパティとして
    // 保持し、テスト実行(assert 時点)まで生存させる。recentRepositoriesMenuDelegate だけは
    // 呼び出し側で識別を検証したいケースがあるため、そちらは引数として個別に受け取る。
    private let recentMenuDelegate = StubMenuDelegate()
    private let bookmarksMenuDelegate = StubMenuDelegate()

    private func buildMenu(recentRepositoriesMenuDelegate: NSMenuDelegate = StubMenuDelegate()) -> NSMenu {
        // swift test のプロセスでは NSApp が未初期化のため、
        // MainMenuBuilder が参照する前に NSApplication.shared で初期化する
        _ = NSApplication.shared
        return MainMenuBuilder.build(
            openAction: #selector(AppDelegate.showOpenPanel),
            helpActions: MainMenuHelpActions(
                visitWebsite: #selector(AppDelegate.openHelp(_:)),
                featureOverview: #selector(AppDelegate.showFeatureOverview(_:)),
                keyboardShortcuts: #selector(AppDelegate.showKeyboardShortcuts(_:)),
                aiIntegration: #selector(AppDelegate.showAIIntegration(_:)),
                ossAcknowledgements: #selector(AppDelegate.showOSSLicenses(_:))
            ),
            recentMenuDelegate: recentMenuDelegate,
            bookmarksMenuDelegate: bookmarksMenuDelegate,
            recentRepositoriesMenuDelegate: recentRepositoriesMenuDelegate
        )
    }

    /// メニュータイトルは実行環境の言語で解決されるため、
    /// テストも Localizable.xcstrings 経由で期待値を得る。
    private func localizedTitle(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .l10n)
    }

    private func submenu(titledKey key: String.LocalizationValue, in mainMenu: NSMenu) -> NSMenu? {
        let title = localizedTitle(key)
        return mainMenu.items.first { $0.submenu?.title == title }?.submenu
    }

    @Test("トップレベルは App/File/Edit/View/Window/Help の 6 メニュー")
    func topLevelMenusArePresent() {
        let mainMenu = buildMenu()

        #expect(mainMenu.items.count == 6)
        let titles = mainMenu.items.compactMap(\.submenu?.title)
        #expect(titles.contains(localizedTitle("menu.file.title")))
        #expect(titles.contains(localizedTitle("menu.edit.title")))
        #expect(titles.contains(localizedTitle("menu.view.title")))
        #expect(titles.contains(localizedTitle("menu.window.title")))
        #expect(titles.contains(localizedTitle("menu.help.title")))
    }

    @Test("File メニューの記憶済みリストは 履歴2つ → Bookmarks の順で並ぶ")
    func fileMenuListsHistoriesBeforeBookmarks() throws {
        let mainMenu = buildMenu()
        let file = try #require(submenu(titledKey: "menu.file.title", in: mainMenu))

        let recentIndex = try #require(file.items.firstIndex {
            $0.submenu?.title == localizedTitle("menu.file.openRecent")
        })
        let recentRepositoriesIndex = try #require(file.items.firstIndex {
            $0.submenu?.title == localizedTitle("menu.file.recentRepositories")
        })
        let bookmarksIndex = try #require(file.items.firstIndex {
            $0.submenu?.title == localizedTitle("menu.file.bookmarks")
        })
        #expect(recentRepositoriesIndex == recentIndex + 1)
        #expect(bookmarksIndex == recentRepositoriesIndex + 1)
        // 「開くコマンド」群とは区切り線で分かれ、リスト群の直後も区切り線で閉じる。
        #expect(file.items[recentIndex - 1].isSeparatorItem)
        #expect(file.items[bookmarksIndex + 1].isSeparatorItem)
    }

    @Test("File メニューに Recent Repositories サブメニューがある")
    func fileMenuHasRecentRepositoriesSubmenu() throws {
        // NSMenu.delegate は weak のため、テストのスコープ内で強参照を保持しておく
        // (build() 呼び出し中だけの参照だと、代入直後に解放されて nil になる)。
        let delegate = StubMenuDelegate()
        let mainMenu = buildMenu(recentRepositoriesMenuDelegate: delegate)
        let file = try #require(submenu(titledKey: "menu.file.title", in: mainMenu))

        let recentRepositoriesItem = try #require(file.items.first {
            $0.submenu?.title == localizedTitle("menu.file.recentRepositories")
        })
        #expect(recentRepositoriesItem.submenu?.delegate === delegate)
    }

    @Test("Edit メニューに Copy(⌘C) と Select All(⌘A) がある")
    func editMenuEnablesCopyAndSelectAll() throws {
        let mainMenu = buildMenu()
        let edit = try #require(submenu(titledKey: "menu.edit.title", in: mainMenu))

        let copy = try #require(edit.items.first { $0.action == #selector(NSText.copy(_:)) })
        #expect(copy.keyEquivalent == "c")
        let selectAll = try #require(edit.items.first { $0.action == #selector(NSText.selectAll(_:)) })
        #expect(selectAll.keyEquivalent == "a")
    }

    @Test("View メニューにズームとフルスクリーンがある")
    func viewMenuHasZoomAndFullScreen() throws {
        let mainMenu = buildMenu()
        let view = try #require(submenu(titledKey: "menu.view.title", in: mainMenu))

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
        let mainMenu = buildMenu()
        let menu = try #require(submenu(titledKey: String.LocalizationValue(submenuKey), in: mainMenu))

        let item = try #require(menu.items.first { $0.action == selector })
        #expect(item.keyEquivalent == key)
        if let modifiers {
            #expect(item.keyEquivalentModifierMask == modifiers)
        }
    }

    @Test("Window メニューにタブ操作項目がある")
    func windowMenuHasTabItems() throws {
        let mainMenu = buildMenu()
        let window = try #require(submenu(titledKey: "menu.window.title", in: mainMenu))

        #expect(window.items.contains { $0.action == #selector(NSWindow.selectNextTab(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.selectPreviousTab(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.moveTabToNewWindow(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.mergeAllWindows(_:)) })
    }

    @Test("Help メニューが NSApp.helpMenu に登録される")
    func helpMenuIsRegistered() throws {
        let mainMenu = buildMenu()
        let help = try #require(submenu(titledKey: "menu.help.title", in: mainMenu))

        #expect(NSApp.helpMenu === help)
        #expect(help.items.contains { $0.action == #selector(AppDelegate.openHelp(_:)) })
    }

    /// 設定は dev 限定のフィーチャーゲートを外して stable でも常に出す(TASK-184)。
    @Test("App メニューに Settings…(⌘,) 項目がビルド種別に関わらずある")
    func appMenuHasSettingsItem() throws {
        let mainMenu = buildMenu()
        let appMenu = try #require(mainMenu.items.first?.submenu)

        let settings = try #require(
            appMenu.items.first { $0.action == #selector(AppDelegate.showSettings(_:)) }
        )
        #expect(settings.title == localizedTitle("menu.app.settings"))
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == [.command])
    }

    @Test("App メニューに Install CLI 項目がある")
    func appMenuHasInstallCLIItem() throws {
        let mainMenu = buildMenu()
        let appMenu = try #require(mainMenu.items.first?.submenu)

        let installItem = try #require(
            appMenu.items.first { $0.action == #selector(AppDelegate.installCLI(_:)) }
        )
        #expect(installItem.title == localizedTitle("menu.app.installCLI"))
    }
}
