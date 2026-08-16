import AppKit

/// メインメニューから「キー等価が割り当てられた項目」を抜き出した一覧。
///
/// Help > キーボードショートカット はこの一覧をそのまま表示する。以前は同じ内容を
/// ビュー側にハードコードしていたが、MainMenuBuilder の変更に追従できず乖離するため、
/// メニュー定義を唯一の情報源にして生成する方式へ変更した(TASK-240)。
@MainActor
enum MenuShortcutCatalog {
    /// ショートカット 1 件。title はメニュー項目の表示名(ローカライズ済み)。
    /// 表示の器は非メニュー由来の一覧と共通(TASK-503)。
    typealias Entry = ShortcutEntry

    /// トップレベルメニュー 1 つ分のまとまり。
    typealias Group = ShortcutSection

    /// AppDelegate が起動時に記録する、Help の一覧表示用スナップショット。
    ///
    /// NSApp.mainMenu を直接読まないのは、AppKit がメニュー設定後に Close All(⌥⌘W)や
    /// Start Dictation などの項目を差し込むため。自前で定義したショートカットだけを
    /// 一覧に載せたいので、mainMenu へ設定する前の状態を保持しておく。
    static var snapshot: [Group] = []

    /// トップレベルメニューごとに、キー等価を持つ項目を抽出する。
    ///
    /// - Parameter appMenuTitle: 先頭のアプリメニューは NSMenu のタイトルが空のため、
    ///   表示に使う名前を呼び出し側から与える。
    /// - Note: Open Recent などの動的サブメニューは中身が実行時に決まり、
    ///   ショートカットも持たないため辿らない(トップレベル直下のみを見る)。
    static func groups(from mainMenu: NSMenu, appMenuTitle: String) -> [Group] {
        mainMenu.items.compactMap { topLevelItem in
            guard let submenu = topLevelItem.submenu else { return nil }
            let entries = submenu.items
                .filter { !$0.keyEquivalent.isEmpty }
                .map { Entry(title: $0.title, key: keyDisplay(of: $0)) }
            guard !entries.isEmpty else { return nil }
            let title = submenu.title.isEmpty ? appMenuTitle : submenu.title
            return Group(title: title, entries: entries)
        }
    }

    /// メニュー項目のキー等価を ⌃⌥⇧⌘ の標準順で表記する(例: ⇧⌘Z)。
    /// 並び順の規則は `ShortcutKey` が持つ(非メニュー由来の項目と同じ表記にするため)。
    static func keyDisplay(of item: NSMenuItem) -> String {
        ShortcutKey(menuItem: item).displayName
    }
}
