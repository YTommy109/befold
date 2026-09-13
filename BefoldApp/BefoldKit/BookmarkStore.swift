import Foundation

/// ブックマーク(`BookmarkLibrary`)を UserDefaults に永続化するストア。
/// GUI(befold)・CLI(befold-cli)双方から同じ実装を使う(befold-cli は `UserDefaults(suiteName:)`
/// で GUI アプリのバンドル ID を指定して同じ永続化領域を参照する)。
/// Recent と異なりユーザーの明示操作でのみ増減するため、上限による自動プルーニングは行わない。
///
/// 操作の中身は値型 `BookmarkLibrary` にあり、この型は「読む → 1 操作 → 書く」だけを担う。
///
/// **デコード済みの値をメモリに持つ。** `isBookmarked` は `validateMenuItem` やツールバーの
/// 再同期から高頻度で呼ばれるため、そのたびに JSON をデコードしない。前提は「同一プロセスで
/// 書くのはこのインスタンスだけ」——GUI では `AppStores` が 1 個だけ持ち、CLI は GUI 起動中は
/// 書かず転送する(`CLIBookmarkRouter`)。別インスタンスが同じ defaults へ書く構成にしたら
/// この前提が破れるので、その場合はここを毎回読む形へ戻すこと。
@MainActor
public final class BookmarkStore {
    private static let defaultsKey = "Bookmarks"
    /// 正規化パスの配列だけを持っていた旧形式のキー。`init` で一度だけ移行し、必ず消す。
    private static let legacyDefaultsKey = "BookmarkedPaths"

    private let defaults: UserDefaults
    private var cached: BookmarkLibrary?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        Self.migrateLegacyPathsIfNeeded(defaults: defaults)
    }

    /// 現在のブックマーク全体。表示や一覧の組み立てはこの値から行う。
    public func library() -> BookmarkLibrary {
        if let cached { return cached }
        let loaded = Self.load(from: defaults)
        cached = loaded
        return loaded
    }

    /// 指定 URL がブックマーク済みかどうかを返す。
    public func isBookmarked(_ url: URL) -> Bool {
        library().contains(url)
    }

    /// 指定 URL をブックマークに追加する。既に追加済みなら何もしない(冪等)。
    /// `befold --bookmark` から(GUI 起動中は転送経由で)呼ばれる。追加先は常にルート直下・別名なし。
    public func add(_ url: URL) {
        mutate { $0.add(url) }
    }

    /// 指定フォルダーの直下へ追加する(管理パネルへのドロップ用)。規則は `BookmarkLibrary.add(_:to:)`。
    public func add(_ url: URL, toFolder folder: [String]) {
        mutate { $0.add(url, to: folder) }
    }

    /// ブックマークの有無を反転させる。
    public func toggle(_ url: URL) {
        if isBookmarked(url) {
            remove(url)
        } else {
            add(url)
        }
    }

    /// 指定 URL をブックマークから取り除く。未登録なら何もしない(冪等)。
    /// 開けないファイル(削除済み・移動済み)をユーザーが明示的に外す経路が使う。
    public func remove(_ url: URL) {
        mutate { $0.remove(url) }
    }

    /// 指定 URL 群をまとめて取り除く。書き込みは 1 回で、取り除く対象が 1 件も無ければ書かない。
    public func removeAll(_ urls: [URL]) {
        mutate { $0.removeAll(urls) }
    }

    /// ブックマーク済みの URL を返す(全フォルダーを平坦化した保存順。表示時にソートする)。
    public func bookmarkedURLs() -> [URL] {
        library().urls
    }

    /// 別名を設定する。空なら別名なしに戻す。未登録の URL には何もしない。
    public func setAlias(_ alias: String?, for url: URL) {
        mutate { $0.setAlias(alias, for: url) }
    }

    /// rename / move をブックマーク状態に反映する。ブックマークされていなければ何もしない。
    /// パスだけが変わり、別名と所属フォルダーは保たれる。
    public func noteRenamed(from oldURL: URL, to newURL: URL) {
        mutate { $0.replace(oldURL, with: newURL) }
    }

    // MARK: - フォルダー(規則は BookmarkLibrary の同名メソッドを参照)

    @discardableResult
    public func createFolder(named name: String, in parent: [String]) -> Bool {
        mutate { $0.createFolder(named: name, in: parent) }
    }

    @discardableResult
    public func renameFolder(at path: [String], to name: String) -> Bool {
        mutate { $0.renameFolder(at: path, to: name) }
    }

    @discardableResult
    public func deleteFolder(at path: [String]) -> Bool {
        mutate { $0.deleteFolder(at: path) }
    }

    @discardableResult
    public func move(_ url: URL, toFolder folder: [String]) -> Bool {
        mutate { $0.move(url, to: folder) }
    }

    public func setFolderExpanded(_ isExpanded: Bool, at path: [String]) {
        mutate { $0.setExpanded(isExpanded, for: path) }
    }

    // MARK: - Private

    /// 1 操作を適用し、値が変わったときだけ書く。操作の戻り値(成否など)はそのまま返す。
    private func mutate<T>(_ body: (inout BookmarkLibrary) -> T) -> T {
        let before = library()
        var after = before
        let result = body(&after)
        if after != before {
            Self.save(after, to: defaults)
            cached = after
        }
        return result
    }

    /// 未保存とデコード不能はどちらも空として読む。フィールドは optional でしか足さない方針
    /// (`BookmarkEntry` の doc)なので、デコード不能は本来到達しない。
    private static func load(from defaults: UserDefaults) -> BookmarkLibrary {
        guard let data = defaults.data(forKey: defaultsKey),
              let library = try? JSONDecoder().decode(BookmarkLibrary.self, from: data)
        else { return BookmarkLibrary() }
        return library
    }

    private static func save(_ library: BookmarkLibrary, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// 旧キーの配列を新キーへ 1 度だけ写す。新キーが既にあれば写さない(以後は新キーだけが真実の源)。
    /// 旧キー自体は移行の有無にかかわらず消す(CLAUDE.md「UserDefaults キーの廃止・改名」)。
    /// 読み手が居ないまま残すと、次に同名のキーを再利用したとき誤って読まれる。
    private static func migrateLegacyPathsIfNeeded(defaults: UserDefaults) {
        defer { defaults.removeObject(forKey: legacyDefaultsKey) }
        guard defaults.data(forKey: defaultsKey) == nil,
              let paths = defaults.stringArray(forKey: legacyDefaultsKey)
        else { return }
        save(BookmarkLibrary.migrated(fromPaths: paths), to: defaults)
    }
}
