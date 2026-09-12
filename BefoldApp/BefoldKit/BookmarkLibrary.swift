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

    /// 一覧に出す名前(名前列の末尾)。
    public var name: String {
        path.last ?? ""
    }
}

/// あるフォルダー直下の中身。フォルダーが先(名前順)、エントリが後(表示名順)。
public struct BookmarkChildren: Equatable, Sendable {
    public var folders: [BookmarkFolder]
    public var entries: [BookmarkEntry]

    public var isEmpty: Bool {
        folders.isEmpty && entries.isEmpty
    }
}

/// ブックマーク全体の値。木ではなく名前列で階層を表すため、全操作が配列の filter / map で書け、
/// `Codable` は合成で足りる。純粋な操作はすべてここに置き、永続化(`BookmarkStore`)は
/// 「読む → 1 操作 → 書く」の薄い層に保つ。
///
/// 不変条件: 1 つのパスは 1 件 / 同じ親の下でフォルダー名は一意 / エントリの所属は存在する
/// フォルダーかルート。操作側で守り、読み出し(`children(of:)`)は記録の無い所属を持つ
/// エントリ(手編集・旧版)をルート扱いにして見えなくならないようにする。
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

    // MARK: - 読み出し

    /// 全フォルダーを平坦化した URL の一覧(保存順)。
    public var urls: [URL] {
        entries.map(\.url)
    }

    /// 一覧に出す順(表示名順)。メニューとパネルが同じ順で並ぶよう、順序の規則はここ 1 箇所に置く。
    /// 比較は Finder と同じ `localizedStandardCompare`(大文字小文字を区別せず、数字は数値順)。
    /// 素の `<` だと別名の "Zulu" がファイル名の "apple.md" より前に来る(大文字が先に並ぶ)。
    public var entriesSortedByDisplayName: [BookmarkEntry] {
        entries.sorted(by: Self.displayOrder)
    }

    /// 全フォルダーを経路順(親 → 子、同じ親では名前順)で。「フォルダーへ移動」の候補に使う。
    public var foldersSortedByPath: [BookmarkFolder] {
        folders.sorted { Self.ascending($0.path.joined(separator: "/"), $1.path.joined(separator: "/")) }
    }

    public func contains(_ url: URL) -> Bool {
        entry(for: url) != nil
    }

    public func entry(for url: URL) -> BookmarkEntry? {
        entry(atPath: url.normalizedPathKey)
    }

    /// 正規化パスで引く(一覧の行 id からエントリへ戻すとき用)。
    public func entry(atPath path: String) -> BookmarkEntry? {
        entries.first { $0.path == path }
    }

    /// ルート(`[]`)は常に存在する。
    public func folderExists(_ path: [String]) -> Bool {
        path.isEmpty || folders.contains { $0.path == path }
    }

    /// エントリの所属。記録の無いフォルダーを指していればルート扱い。
    public func resolvedFolder(of entry: BookmarkEntry) -> [String] {
        folderExists(entry.folder) ? entry.folder : []
    }

    /// `parent` 直下の中身。フォルダーが先(名前順)、エントリが後(表示名順)。
    public func children(of parent: [String]) -> BookmarkChildren {
        let subfolders = folders
            .filter { $0.path.count == parent.count + 1 && $0.path.starts(with: parent) }
            .sorted { Self.ascending($0.name, $1.name) }
        let members = entries
            .filter { resolvedFolder(of: $0) == parent }
            .sorted(by: Self.displayOrder)
        return BookmarkChildren(folders: subfolders, entries: members)
    }

    // MARK: - エントリの操作

    /// 未登録ならルート直下へ追加する。登録済みなら何もしない(冪等)。
    public mutating func add(_ url: URL) {
        add(url, to: [])
    }

    /// 未登録なら `folder` の直下へ追加する。登録済みなら何もしない(所属も変えない)。
    /// フォルダーが無ければルートへ入れる(ドロップ中にフォルダーが消えても取りこぼさない)。
    public mutating func add(_ url: URL, to folder: [String]) {
        guard !contains(url) else { return }
        entries.append(BookmarkEntry(path: url.normalizedPathKey, folder: folderExists(folder) ? folder : []))
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
        let trimmed = Self.trimmed(alias)
        entries[index].alias = trimmed.isEmpty ? nil : trimmed
    }

    /// エントリを別のフォルダー(ルートは `[]`)へ移す。フォルダーが無い・未登録なら false。
    @discardableResult
    public mutating func move(_ url: URL, to folder: [String]) -> Bool {
        guard folderExists(folder), let index = index(of: url) else { return false }
        entries[index].folder = folder
        return true
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

    // MARK: - フォルダーの操作

    /// 入力をフォルダー名に正規化する(前後の空白を除き、空なら nil)。
    /// 作成・改名の中と、入力欄を持つ側の事前判定が同じ規則を使う(規則を写して持たない)。
    public static func folderName(_ text: String) -> String? {
        let name = trimmed(text)
        return name.isEmpty ? nil : name
    }

    /// `parent` の下にフォルダーを作る。空の名前・親が無い・同名の兄弟がいれば false。
    @discardableResult
    public mutating func createFolder(named name: String, in parent: [String]) -> Bool {
        guard let name = Self.folderName(name), folderExists(parent) else { return false }
        let path = parent + [name]
        guard !folderExists(path) else { return false }
        folders.append(BookmarkFolder(path: path))
        return true
    }

    /// フォルダーを改名する。配下のサブフォルダーとエントリの所属も全件追随する。
    /// 同名の兄弟がいれば false。同じ名前への改名は何もせず true。
    @discardableResult
    public mutating func renameFolder(at path: [String], to name: String) -> Bool {
        guard !path.isEmpty, let name = Self.folderName(name), folderExists(path) else { return false }
        let newPath = Array(path.dropLast()) + [name]
        if newPath == path { return true }
        guard !folderExists(newPath) else { return false }
        rewritePrefix(path, to: newPath)
        return true
    }

    /// フォルダーを消す。**配下のサブフォルダーとエントリは親へ繰り上げる**(失われない)。
    /// 繰り上げ先に同名のフォルダーがあれば何もせず false(改名と同じ規則)。
    @discardableResult
    public mutating func deleteFolder(at path: [String]) -> Bool {
        guard !path.isEmpty, folderExists(path) else { return false }
        let parent = Array(path.dropLast())
        let promoted = children(of: path).folders.map { parent + [$0.name] }
        guard !promoted.contains(where: folderExists) else { return false }
        folders.removeAll { $0.path == path }
        rewritePrefix(path, to: parent)
        return true
    }

    /// 展開状態を記録する。フォルダーが無ければ何もしない。
    public mutating func setExpanded(_ isExpanded: Bool, for path: [String]) {
        guard let index = folders.firstIndex(where: { $0.path == path }) else { return }
        folders[index].isExpanded = isExpanded
    }

    // MARK: - Private

    private func index(of url: URL) -> Int? {
        let path = url.normalizedPathKey
        return entries.firstIndex { $0.path == path }
    }

    /// `old` で始まる名前列(フォルダー自身・サブフォルダー・エントリの所属)を `new` 始まりへ書き換える。
    private mutating func rewritePrefix(_ old: [String], to new: [String]) {
        for index in folders.indices where folders[index].path.starts(with: old) {
            folders[index].path = new + folders[index].path.dropFirst(old.count)
        }
        for index in entries.indices where entries[index].folder.starts(with: old) {
            entries[index].folder = new + entries[index].folder.dropFirst(old.count)
        }
    }

    private static func trimmed(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func ascending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func displayOrder(_ lhs: BookmarkEntry, _ rhs: BookmarkEntry) -> Bool {
        ascending(lhs.displayName, rhs.displayName)
    }
}
