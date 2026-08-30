import Foundation

/// ビューア内のキー操作を Help > キーボードショートカット に載せるための一覧。
///
/// **この一覧は web 面(WKWebView)と PDF 面の両方を指す。** 割り当てが同じだからで、
/// PDF 面は `PDFSurfaceLayout.keyboardScroll(forKey:shift:)` が同じ表を持つ(TASK-577)。
/// 送り量までは一致しない(PDF の Space はページ区切りに合わせてオーバーラップ無し)。
/// 片面にだけキーを足すとこの前提が崩れるので、足すなら両面へ足す。
///
/// 割り当ての実体は JavaScript 側にあり(`viewer-src/keyboard.js` の `resolveScrollKey` /
/// `resolveBarCloseKey`)、Swift からは呼べない。そこで **この宣言を jest 側がパースして
/// 実装と突き合わせる**(`BefoldKit/Resources/__tests__/viewerShortcutCatalog.test.js`)。
/// 配布サイトが `MainMenuBuilder*.swift` を読んでページ記載のずれを検出しているのと同じ
/// 手口で、言語をまたぐ乖離を機械的に落とす(TASK-503)。
///
/// **リテラル形式と配列名は上記テストのパーサと対になっている。** 引数名・配列名・並びを
/// 変えるときはテスト側の正規表現も合わせること(空白・改行の入り方には依存しないので、
/// swiftformat の折り返しは気にしなくてよい)。配列ごとのパース件数が
/// `ViewerShortcutCatalogTests` の期待値と食い違えばテストが失敗する
/// —— 空集合に対する検証は素通りしてしまうため、0 件を成功にしない。
enum ViewerShortcutCatalog {
    /// JS 側の解決結果に対応する期待値。rawValue がそのまま jest 側の期待表になる。
    enum Expectation: String {
        case pageDown, pageUp
        case lineDown, lineUp
        case halfPageDown, halfPageUp
        /// Esc: 開いているのが検索バーだけの構成(ゲート閉)での説明。
        case findClose
        /// Esc: ジャンプバーも開きうる構成(ゲート開)での説明。
        case barClose
        case jumpNext, jumpPrev
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

    /// スクロールのキー。ゲートによらず常に載せる。
    static let scrollItems: [Item] = [
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
    ]

    /// 文書内ジャンプ(TASK-485)がゲート閉のときの Esc。開けるバーが検索バーしか無いため、
    /// 説明も「検索バーを閉じる」に閉じる。
    static let findOnlyItems: [Item] = [
        Item(jsKeys: ["Escape"], shift: false, expects: .findClose, titleKey: "shortcuts.viewer.findClose"),
    ]

    /// 文書内ジャンプがゲート開のときに載せる行。Esc は検索バーとジャンプバーの
    /// どちらも閉じるため、findOnlyItems の 1 行と**入れ替える**(併記しない)。
    /// ゲート閉のビルドでジャンプのキー操作を告知しないのは TASK-485.8 の判断に揃えたもの。
    static let documentJumpItems: [Item] = [
        Item(jsKeys: ["Escape"], shift: false, expects: .barClose, titleKey: "shortcuts.viewer.barClose"),
        Item(jsKeys: ["Enter"], shift: false, expects: .jumpNext, titleKey: "shortcuts.viewer.jumpNext"),
        Item(jsKeys: ["Enter"], shift: true, expects: .jumpPrev, titleKey: "shortcuts.viewer.jumpPrev"),
    ]

    /// 実際に一覧へ並べる行。ゲートの値は呼び出し側が渡す(既定値は付けない —— 付けると
    /// 渡し忘れが黙って通る。TASK-485.8 と同じ理由)。
    static func items(isDocumentJumpEnabled: Bool) -> [Item] {
        scrollItems + (isDocumentJumpEnabled ? documentJumpItems : findOnlyItems)
    }

    static func section(isDocumentJumpEnabled: Bool) -> ShortcutSection {
        ShortcutSection(
            title: String(localized: .init(sectionTitleKey), bundle: .l10n),
            entries: items(isDocumentJumpEnabled: isDocumentJumpEnabled).map { item in
                ShortcutEntry(
                    title: String(localized: .init(item.titleKey), bundle: .l10n),
                    keys: item.jsKeys.map { ShortcutKey(viewerKey: $0, shift: item.shift) }
                )
            }
        )
    }
}
