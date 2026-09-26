import Foundation

/// Help > キーボードショートカット に並べるセクション全体(TASK-503)。
///
/// メニュー由来(`MenuShortcutCatalog`)と、メニューを経由しない操作の一覧を連結する。
/// 由来ごとにセクションを分けるのは、メニュー由来の抽出をこれまでどおり
/// 「NSMenu が唯一の情報源」のまま保つため(TASK-240 の判断を薄めない)。
/// 非メニュー由来の各カタログは、それぞれの実装の隣に置き、突合テストで縛る。
@MainActor
enum HelpShortcutSections {
    /// 非メニュー由来の項目が使うローカライズキー。訳が無いと Help にキー文字列が
    /// そのまま並ぶため、`LocalizationTests` が全キーの en / ja を検証する。
    /// (swift test では String Catalog がコンパイルされず `String(localized:)` が
    /// キーをそのまま返すので、表示結果ではなくカタログ側で確かめる)
    static var localizationKeys: [String] {
        [ViewerShortcutCatalog.sectionTitleKey]
            + ViewerShortcutCatalog.items.map(\.titleKey)
            + [SidebarShortcutCatalog.sectionTitleKey]
            + SidebarShortcutCatalog.items.map(\.titleKey)
            + [QuickOpenShortcutCatalog.sectionTitleKey]
            + QuickOpenShortcutCatalog.items.map(\.titleKey)
    }

    static var all: [ShortcutSection] {
        MenuShortcutCatalog.snapshot + [
            ViewerShortcutCatalog.section,
            SidebarShortcutCatalog.section,
            QuickOpenShortcutCatalog.section,
        ]
    }
}
