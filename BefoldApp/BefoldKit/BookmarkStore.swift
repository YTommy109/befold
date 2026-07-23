import Foundation

/// ファイル単位のブックマーク状態を UserDefaults に永続化するストア。
/// GUI(befold)・CLI(befold-cli)双方から同じ実装を使う(befold-cli は `UserDefaults(suiteName:)`
/// で GUI アプリのバンドル ID を指定して同じ永続化領域を参照する)。
/// Recent と異なりユーザーの明示操作でのみ増減するため、上限による自動プルーニングは行わない。
@MainActor
public final class BookmarkStore {
    private static let defaultsKey = "BookmarkedPaths"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 指定 URL がブックマーク済みかどうかを返す。
    public func isBookmarked(_ url: URL) -> Bool {
        savedPaths().contains(url.normalizedPathKey)
    }

    /// 指定 URL をブックマークに追加する。既に追加済みなら何もしない(冪等)。
    /// `befold bookmark add` サブコマンドから呼ばれる。
    public func add(_ url: URL) {
        let path = url.normalizedPathKey
        var paths = savedPaths()
        guard !paths.contains(path) else { return }
        paths.append(path)
        save(paths)
    }

    /// ブックマークの有無を反転させる。
    public func toggle(_ url: URL) {
        let path = url.normalizedPathKey
        var paths = savedPaths()
        if let index = paths.firstIndex(of: path) {
            paths.remove(at: index)
        } else {
            paths.append(path)
        }
        save(paths)
    }

    /// ブックマーク済みの URL を返す(順序は保持しない。表示時にソートする)。
    public func bookmarkedURLs() -> [URL] {
        savedPaths().map { URL(fileURLWithPath: $0) }
    }

    /// rename / move をブックマーク状態に反映する。ブックマークされていなければ何もしない。
    public func noteRenamed(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.normalizedPathKey
        var paths = savedPaths()
        guard let index = paths.firstIndex(of: oldPath) else { return }
        paths[index] = newURL.normalizedPathKey
        save(paths)
    }

    private func savedPaths() -> [String] {
        defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    private func save(_ paths: [String]) {
        defaults.set(paths, forKey: Self.defaultsKey)
    }
}
