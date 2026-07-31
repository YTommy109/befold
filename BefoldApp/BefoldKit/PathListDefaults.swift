import Foundation

/// UserDefaults に「正規化パスの配列」を永続化するための共通プリミティブ。
///
/// SessionStore / BookmarkStore / RecentDocumentsStore などのストアは
/// 「`stringArray(forKey:) ?? []` を読み、`normalizedPathKey` で操作し、`set(_:forKey:)` で書く」
/// という同じ骨組みを持つ。その骨組みだけをここに集約し、各ストアはドメイン API
/// (freeze / seedIfNeeded など)をこのプリミティブの合成として書く。
///
/// `limit` を指定すると、書き込みのたびに先頭から `limit` 件へ切り詰める(Recent の上限用)。
public struct PathListDefaults {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int?

    /// - Parameters:
    ///   - defaults: 永続化先。
    ///   - key: UserDefaults のキー。
    ///   - limit: 保存件数の上限。nil なら無制限。
    public init(defaults: UserDefaults, key: String, limit: Int? = nil) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    /// 保存済みの正規化パスを保存順で返す。未保存なら空配列。
    public var paths: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// 保存済みのパスを URL にして返す。
    public var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    /// 一度でも保存されているかどうか(空配列の保存と未保存を区別する)。
    public var hasStoredValue: Bool {
        defaults.object(forKey: key) != nil
    }

    /// 指定 URL が保存済みかどうかを返す。
    public func contains(_ url: URL) -> Bool {
        paths.contains(url.normalizedPathKey)
    }

    /// 配列全体を置き換える(上限があれば切り詰める)。
    public func replaceAll(with paths: [String]) {
        defaults.set(limit.map { Array(paths.prefix($0)) } ?? paths, forKey: key)
    }

    /// 配列全体を URL 列で置き換える。
    public func replaceAll(withURLs urls: [URL]) {
        replaceAll(with: urls.map(\.normalizedPathKey))
    }

    /// 未登録なら末尾に追加する。登録済みなら順序を保ったまま何もしない。
    public func appendIfAbsent(_ url: URL) {
        let path = url.normalizedPathKey
        var paths = paths
        guard !paths.contains(path) else { return }
        paths.append(path)
        replaceAll(with: paths)
    }

    /// 先頭へ移動する(未登録なら先頭に追加する)。
    public func moveToFront(_ url: URL) {
        let path = url.normalizedPathKey
        var paths = paths.filter { $0 != path }
        paths.insert(path, at: 0)
        replaceAll(with: paths)
    }

    /// 指定 URL を取り除く。未登録なら配列は変わらない。
    public func remove(_ url: URL) {
        let path = url.normalizedPathKey
        replaceAll(with: paths.filter { $0 != path })
    }

    /// 登録済みなら取り除き、未登録なら末尾に追加する。
    public func toggle(_ url: URL) {
        if contains(url) {
            remove(url)
        } else {
            appendIfAbsent(url)
        }
    }

    /// 旧 URL を新 URL へその場で置き換える(位置を保つ)。旧 URL が未登録なら何もしない。
    public func replace(_ oldURL: URL, with newURL: URL) {
        let oldPath = oldURL.normalizedPathKey
        var paths = paths
        guard let index = paths.firstIndex(of: oldPath) else { return }
        paths[index] = newURL.normalizedPathKey
        replaceAll(with: paths)
    }
}
