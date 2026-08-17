import Foundation

/// ビューア(WKWebView)内のキー操作を Help > キーボードショートカット に載せるための一覧。
///
/// 割り当ての実体は JavaScript 側にあり(`viewer-src/keyboard.js` の `resolveScrollKey` /
/// `resolveBarCloseKey`)、Swift からは呼べない。そこで **この宣言を jest 側がパースして
/// 実装と突き合わせる**(`BefoldKit/Resources/__tests__/viewerShortcutCatalog.test.js`)。
/// 配布サイトが `MainMenuBuilder*.swift` を読んでページ記載のずれを検出しているのと同じ
/// 手口で、言語をまたぐ乖離を機械的に落とす(TASK-503)。
///
/// **`items` のリテラル形式は上記テストのパーサと対になっている。** 引数名や並びを
/// 変えるときはテスト側の正規表現も合わせること(空白・改行の入り方には依存しないので、
/// swiftformat の折り返しは気にしなくてよい)。パースした件数が
/// `ViewerShortcutCatalogTests.expectedItemCount` と食い違えばテストが失敗する
/// —— 空集合に対する検証は素通りしてしまうため、0 件を成功にしない。
enum ViewerShortcutCatalog {
    /// JS 側の解決結果に対応する期待値。rawValue がそのまま jest 側の期待表になる。
    enum Expectation: String {
        case pageDown, pageUp
        case lineDown, lineUp
        case halfPageDown, halfPageUp
        case findClose
    }

    /// 一覧の 1 行。`jsKeys` は KeyboardEvent.key の値で、表示するキー表記もここから導く。
    struct Item {
        let jsKeys: [String]
        let shift: Bool
        let expects: Expectation
        let titleKey: String
    }

    /// 見出しのローカライズキー。訳の有無は LocalizationTests が検証する。
    static let sectionTitleKey = "shortcuts.section.viewer"

    static let items: [Item] = [
        Item(jsKeys: [" "], shift: false, expects: .pageDown, titleKey: "shortcuts.viewer.pageDown"),
        Item(jsKeys: [" "], shift: true, expects: .pageUp, titleKey: "shortcuts.viewer.pageUp"),
        Item(jsKeys: ["ArrowDown", "j"], shift: false, expects: .lineDown, titleKey: "shortcuts.viewer.lineDown"),
        Item(jsKeys: ["ArrowUp", "k"], shift: false, expects: .lineUp, titleKey: "shortcuts.viewer.lineUp"),
        Item(
            jsKeys: ["ArrowDown", "j"],
            shift: true,
            expects: .halfPageDown,
            titleKey: "shortcuts.viewer.halfPageDown"
        ),
        Item(jsKeys: ["ArrowUp", "k"], shift: true, expects: .halfPageUp, titleKey: "shortcuts.viewer.halfPageUp"),
        Item(jsKeys: ["Escape"], shift: false, expects: .findClose, titleKey: "shortcuts.viewer.findClose"),
    ]

    static var section: ShortcutSection {
        ShortcutSection(
            title: String(localized: .init(sectionTitleKey), bundle: .l10n),
            entries: items.map { item in
                ShortcutEntry(
                    title: String(localized: .init(item.titleKey), bundle: .l10n),
                    keys: item.jsKeys.map { ShortcutKey(viewerKey: $0, shift: item.shift) }
                )
            }
        )
    }
}
