import SwiftUI

/// サイドバーのキー操作を Help > キーボードショートカット に載せるための一覧(TASK-503)。
///
/// **割り当ての情報源は `SidebarKeyAction.action(key:modifiers:target:mode:)` のままで、
/// ここはその再宣言ではない。** 保持するのは「どのキーを載せるか・何と説明するか」だけで、
/// そのキーが実際に何を起こすかは常にディスパッチ側が決める。表示に出るキー表記も
/// ここに書いた `KeyEquivalent` / `EventModifiers` から導く(別に文字列を持たない)。
///
/// 両者がずれないよう `SidebarShortcutCatalogTests` が双方向に縛る。
/// - 健全性: ここに載せたキーは `action(...)` で `.ignored` 以外へ解決される
/// - 完全性: `action(...)` が反応するキーはすべてここに載っている
///
/// 後者が無いと、ディスパッチにキーを足したときに一覧だけが黙って古くなる
/// (ハードコード表を消した TASK-240 の判断が実質的に破れる)。
enum SidebarShortcutCatalog {
    /// 一覧に載せるキー 1 つ。`SidebarKeyAction.action` へそのまま渡せる形で持つ。
    struct Key {
        let key: KeyEquivalent
        let modifiers: EventModifiers

        init(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) {
            self.key = key
            self.modifiers = modifiers
        }

        var display: ShortcutKey {
            ShortcutKey(key: key, modifiers: modifiers)
        }
    }

    /// 一覧の 1 行。`keys` は同じ説明になるキーの並び(例: ↓ と J)。
    struct Item {
        let keys: [Key]
        let titleKey: String
    }

    /// 見出しのローカライズキー。訳の有無は LocalizationTests が検証する。
    static let sectionTitleKey = "shortcuts.section.sidebar"

    static let items: [Item] = [
        Item(keys: [Key(.downArrow), Key("j")], titleKey: "shortcuts.sidebar.selectNext"),
        Item(keys: [Key(.upArrow), Key("k")], titleKey: "shortcuts.sidebar.selectPrevious"),
        Item(keys: [Key(.rightArrow), Key("l"), Key(.return)], titleKey: "shortcuts.sidebar.forward"),
        Item(keys: [Key(.leftArrow), Key("h")], titleKey: "shortcuts.sidebar.backward"),
        Item(
            keys: [Key(.upArrow, .command), Key(.delete)],
            titleKey: "shortcuts.sidebar.navigateToParent"
        ),
        Item(keys: [Key(.return, .command)], titleKey: "shortcuts.sidebar.openInNewTab"),
        Item(
            keys: [Key(.return, [.command, .shift])],
            titleKey: "shortcuts.sidebar.openInNewWindow"
        ),
    ]

    static var section: ShortcutSection {
        ShortcutSection(
            title: String(localized: .init(sectionTitleKey), bundle: .l10n),
            entries: items.map {
                ShortcutEntry(
                    title: String(localized: .init($0.titleKey), bundle: .l10n),
                    keys: $0.keys.map(\.display)
                )
            }
        )
    }
}
