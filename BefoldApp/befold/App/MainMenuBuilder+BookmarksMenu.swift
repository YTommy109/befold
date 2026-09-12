import AppKit

/// Bookmarks メニューの構築。追加/削除のトグルは View メニュー、一覧は File > Bookmarks
/// サブメニューに分かれていたが、どちらもトップレベルの Bookmarks へ集約した(TASK-535)。
///
/// **ファイル名の `MainMenuBuilder` 接頭辞を保つこと。** 紹介サイトのショートカット検証は
/// `MainMenuBuilder*.swift` の glob でメニュー定義を全件読む(`site/vitest.config.ts` の
/// `readMainMenuBuilderSwift` と `.github/workflows/site.yml` の paths)。別の型名へ出すと
/// 実装とページの突き合わせが片側だけ欠ける。
extension MainMenuBuilder {
    /// 一覧の中身は `delegate`(`BookmarksMenuController`)が表示直前に組み立てる。
    /// 固定部のトグルだけはここでも置く——理由は `addBookmarkToggleItem(to:)` を参照。
    static func makeBookmarksMenuItem(delegate: NSMenuDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.bookmarks.title", bundle: .l10n))
        menu.delegate = delegate
        item.submenu = menu
        addBookmarkToggleItem(to: menu)
        return item
    }

    /// ブックマークの追加/削除トグル。表示名は `ViewerMenuValidator` が
    /// `ViewerCommandTitles.bookmark(isBookmarked:)` で毎回入れ替えるため、ここで付くのは初期値。
    ///
    /// **この関数は組み立て時と一覧の再生成時の両方から呼ばれる。** 一覧を持つ
    /// `BookmarksMenuController` は表示直前に `removeAllItems()` してから作り直すので、
    /// 固定部もそのたびに置き直す必要がある。一方 Help > キーボードショートカット の
    /// スナップショット(`MenuShortcutCatalog.snapshot`)は `NSApp.mainMenu` へ設定する**前の**
    /// メニュー木から取るため、delegate 任せにすると ⌘D が一覧から消える。
    /// 両方を満たす唯一の形が「同じ関数を 2 経路から呼ぶ」で、崩れたら
    /// `MainMenuBuilderTests` と `MenuShortcutCatalogTests` が落ちる。
    static func addBookmarkToggleItem(to menu: NSMenu) {
        menu.addLocalizedItem(
            "menu.bookmarks.add",
            action: #selector(ViewerWindowController.toggleBookmark(_:)),
            keyEquivalent: BookmarkShortcut.keyEquivalent
        )
    }
}
