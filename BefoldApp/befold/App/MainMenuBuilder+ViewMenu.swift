import AppKit

/// View メニューの構築。MainMenuBuilder 本体から分けているのは、swiftlint の
/// type_body_length を超えないようにするため(他のメニュー構築と同じ粒度で切り出す)。
///
/// キー等価の定義は紹介サイトのショートカット表と突き合わせている。読み手は
/// `MainMenuBuilder*.swift` を全件見る形にしてあるので(site/vitest.config.ts と
/// .github/workflows/site.yml の paths)、さらに分割するときもこの命名を保つこと。
extension MainMenuBuilder {
    /// - Parameters:
    ///   - isChangedFilesOnlyAvailable: 「変更されたファイルのみ表示」のゲート値。
    ///     テストから ON/OFF 両方向を確かめられるよう引数で受ける。
    ///   - isTreeLayoutAvailable: サイドバーのツリー表示のゲート値。
    static func makeViewMenuItem(
        isChangedFilesOnlyAvailable: Bool = FeatureGate.isSidebarGitStatusEnabled,
        isTreeLayoutAvailable: Bool = FeatureGate.isSidebarTreeEnabled
    ) -> NSMenuItem {
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
        menu.addItem(.separator())
        addHistoryItems(to: menu)
        menu.addItem(.separator())
        addSidebarItems(
            to: menu,
            isChangedFilesOnlyAvailable: isChangedFilesOnlyAvailable,
            isTreeLayoutAvailable: isTreeLayoutAvailable
        )
        // macOS 標準のフルスクリーン切替ショートカット(⌃⌘F)に合わせる。
        menu.addLocalizedItem(
            "menu.view.enterFullScreen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f",
            modifiers: [.control, .command]
        )
        return item
    }

    /// サイドバーのツリー表示の切替項目。開発中機能(TASK-361)なので露出点でゲートする。
    /// ショートカットは付けない。⌘1〜4 はプレビューの表示モードに割り当て済み(TASK-356)。
    /// - Parameter isTreeLayoutAvailable: ゲート値。テストから両方向を確かめられるよう引数で受ける。
    static func addSidebarTreeLayoutItem(
        to menu: NSMenu, isTreeLayoutAvailable: Bool = FeatureGate.isSidebarTreeEnabled
    ) {
        guard isTreeLayoutAvailable else { return }
        menu.addLocalizedItem(
            "menu.view.sidebarTreeLayout",
            action: #selector(AppDelegate.toggleSidebarTreeLayout(_:))
        )
    }

    /// サイドバーの「変更されたファイルのみ表示」切替項目。開発中機能(TASK-187)なので
    /// 露出点でゲートする。素の ⌘G / ⇧⌘G は Edit メニューの検索送りと衝突するため、
    /// control を重ねて区別する。
    /// - Parameter isChangedFilesOnlyAvailable: ゲート値。テストから両方向を確かめられるよう引数で受ける。
    static func addChangedFilesOnlyItem(
        to menu: NSMenu, isChangedFilesOnlyAvailable: Bool = FeatureGate.isSidebarGitStatusEnabled
    ) {
        guard isChangedFilesOnlyAvailable else { return }
        menu.addLocalizedItem(
            "menu.view.showChangedFilesOnly",
            action: #selector(AppDelegate.toggleChangedFilesOnly(_:)),
            keyEquivalent: "g",
            modifiers: [.command, .control]
        )
    }

    /// View メニューのサイドバー関連項目(不可視ファイル・変更のみ表示・ツリー表示)。
    /// makeViewMenuItem から切り出しているのは、1 関数が長くなりすぎないようにするため。
    /// - Parameters:
    ///   - isChangedFilesOnlyAvailable: 「変更されたファイルのみ表示」のゲート値。
    ///   - isTreeLayoutAvailable: ツリー表示のゲート値。
    static func addSidebarItems(
        to menu: NSMenu,
        isChangedFilesOnlyAvailable: Bool = FeatureGate.isSidebarGitStatusEnabled,
        isTreeLayoutAvailable: Bool = FeatureGate.isSidebarTreeEnabled
    ) {
        // 素の ⌘H は App メニューの Hide(NSApplication.hide)と衝突するため、
        // control を重ねて区別する。
        menu.addLocalizedItem(
            "menu.view.showHiddenFiles",
            action: #selector(AppDelegate.toggleHiddenFiles(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .control]
        )
        addChangedFilesOnlyItem(to: menu, isChangedFilesOnlyAvailable: isChangedFilesOnlyAvailable)
        addSidebarTreeLayoutItem(to: menu, isTreeLayoutAvailable: isTreeLayoutAvailable)
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
