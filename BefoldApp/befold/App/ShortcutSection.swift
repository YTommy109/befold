import Foundation

/// Help > キーボードショートカット に並べる 1 件。
///
/// title は表示済みの文字列で、由来(メニュー項目名 / ローカライズキー)は問わない。
/// key は `ShortcutKey.displayName` を通ったものだけを入れる(表記規則を 1 か所に保つため)。
struct ShortcutEntry: Identifiable {
    let id = UUID()
    let title: String
    let key: String

    init(title: String, key: String) {
        self.title = title
        self.key = key
    }

    init(title: String, keys: [ShortcutKey]) {
        self.init(title: title, key: keys.map(\.displayName).joined(separator: " / "))
    }
}

/// 一覧の見出し 1 つ分。メニュー由来ならトップレベルメニュー 1 つ、
/// 非メニュー由来なら操作の場所(ビューア / サイドバー / Quick Open)にあたる。
struct ShortcutSection: Identifiable {
    let id = UUID()
    let title: String
    let entries: [ShortcutEntry]
}
