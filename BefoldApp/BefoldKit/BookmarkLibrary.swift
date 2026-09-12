import Foundation

/// ブックマーク 1 件。パス(正規化済み)に、任意の別名と所属フォルダーを添える。
///
/// 将来フィールドを足す場合は必ず optional / 既定値ありにすること。旧バージョンが書いた
/// JSON を新バージョンが読む(その逆も)ため、必須フィールドを増やすと既存の保存データが
/// デコード不能になる(`RecentRepositoryEntry` と同じ理由)。
public struct BookmarkEntry: Codable, Equatable, Sendable {
    /// `URL.normalizedPathKey` の形。
    public var path: String
    /// ユーザーが付けた表示名。nil ならファイル名で表示する。空文字は保存しない(`setAlias` が nil へ畳む)。
    public var alias: String?
    /// 所属フォルダーの名前列(ルートからの経路)。`[]` はルート直下。
    public var folder: [String]

    public init(path: String, alias: String? = nil, folder: [String] = []) {
        self.path = path
        self.alias = alias
        self.folder = folder
    }

    public var url: URL {
        URL(fileURLWithPath: path)
    }

    /// 一覧に出す名前。別名があればそれ、無ければファイル名。
    public var displayName: String {
        alias ?? url.lastPathComponent
    }
}

/// ユーザー定義の仮想フォルダー。中身を持たず、空のフォルダーも存在させるために明示的に保存する。
public struct BookmarkFolder: Codable, Equatable, Sendable {
    /// ルートからの名前列。同じ親の下で名前は一意。
    public var path: [String]
    public var isExpanded: Bool

    public init(path: [String], isExpanded: Bool = true) {
        self.path = path
        self.isExpanded = isExpanded
    }
}

/// ブックマーク全体の値。木ではなく名前列で階層を表すため、全操作が配列の filter / map で書け、
/// `Codable` は合成で足りる。純粋な操作はすべてここに置き、永続化(`BookmarkStore`)は
/// 「読む → 1 操作 → 書く」の薄い層に保つ。
public struct BookmarkLibrary: Codable, Equatable, Sendable {
    public var folders: [BookmarkFolder]
    public var entries: [BookmarkEntry]

    public init(folders: [BookmarkFolder] = [], entries: [BookmarkEntry] = []) {
        self.folders = folders
        self.entries = entries
    }

    /// 旧形式(正規化パスの配列)からの変換。全件をルート直下・別名なしのエントリにする。
    public static func migrated(fromPaths paths: [String]) -> BookmarkLibrary {
        var library = BookmarkLibrary()
        for path in paths where !library.entries.contains(where: { $0.path == path }) {
            library.entries.append(BookmarkEntry(path: path))
        }
        return library
    }

    /// 全フォルダーを平坦化した URL の一覧(保存順)。
    public var urls: [URL] {
        entries.map(\.url)
    }

    /// 一覧に出す順(表示名順)。メニューとパネルが同じ順で並ぶよう、順序の規則はここ 1 箇所に置く。
    public var entriesSortedByDisplayName: [BookmarkEntry] {
        entries.sorted { $0.displayName < $1.displayName }
    }

    public func contains(_ url: URL) -> Bool {
        entry(for: url) != nil
    }

    public func entry(for url: URL) -> BookmarkEntry? {
        let path = url.normalizedPathKey
        return entries.first { $0.path == path }
    }

    /// 未登録ならルート直下へ追加する。登録済みなら何もしない(冪等)。
    public mutating func add(_ url: URL) {
        guard !contains(url) else { return }
        entries.append(BookmarkEntry(path: url.normalizedPathKey))
    }

    public mutating func remove(_ url: URL) {
        removeAll([url])
    }

    public mutating func removeAll(_ urls: [URL]) {
        let removed = Set(urls.map(\.normalizedPathKey))
        entries.removeAll { removed.contains($0.path) }
    }

    /// 別名を設定する。前後の空白を除き、空なら別名なし(nil)に畳む。未登録なら何もしない。
    public mutating func setAlias(_ alias: String?, for url: URL) {
        guard let index = index(of: url) else { return }
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        entries[index].alias = trimmed.isEmpty ? nil : trimmed
    }

    /// rename / move を反映する。パスだけを差し替え、別名と所属フォルダーは保つ。
    /// 新パスが別のエントリとして既に載っていればそちらを落とし、1 つのパスが 2 回現れないようにする
    /// (残すのは置き換えた側。`PathListDefaults.replace` と同じ規則)。旧パスが未登録なら何もしない。
    public mutating func replace(_ oldURL: URL, with newURL: URL) {
        guard let index = index(of: oldURL) else { return }
        let newPath = newURL.normalizedPathKey
        entries[index].path = newPath
        entries = entries.enumerated()
            .filter { $0.offset == index || $0.element.path != newPath }
            .map(\.element)
    }

    private func index(of url: URL) -> Int? {
        let path = url.normalizedPathKey
        return entries.firstIndex { $0.path == path }
    }
}
