import Foundation

/// ファイル単位のブックマーク状態を UserDefaults に永続化するストア。
/// GUI(befold)・CLI(befold-cli)双方から同じ実装を使う(befold-cli は `UserDefaults(suiteName:)`
/// で GUI アプリのバンドル ID を指定して同じ永続化領域を参照する)。
/// Recent と異なりユーザーの明示操作でのみ増減するため、上限による自動プルーニングは行わない。
@MainActor
public final class BookmarkStore {
    private static let defaultsKey = "BookmarkedPaths"

    private let bookmarkedPaths: PathListDefaults

    public init(defaults: UserDefaults) {
        bookmarkedPaths = PathListDefaults(defaults: defaults, key: Self.defaultsKey)
    }

    /// 指定 URL がブックマーク済みかどうかを返す。
    public func isBookmarked(_ url: URL) -> Bool {
        bookmarkedPaths.contains(url)
    }

    /// 指定 URL をブックマークに追加する。既に追加済みなら何もしない(冪等)。
    /// `befold bookmark add` サブコマンドから呼ばれる。
    public func add(_ url: URL) {
        bookmarkedPaths.appendIfAbsent(url)
    }

    /// ブックマークの有無を反転させる。
    public func toggle(_ url: URL) {
        bookmarkedPaths.toggle(url)
    }

    /// 指定 URL をブックマークから取り除く。未登録なら何もしない(冪等)。
    /// 開けないファイル(削除済み・移動済み)をユーザーが明示的に外す経路が使う。
    public func remove(_ url: URL) {
        bookmarkedPaths.remove(url)
    }

    /// 指定 URL 群をまとめて取り除く。`remove` の連呼と違い書き込みは 1 回で、
    /// 取り除く対象が 1 件も無ければ書き込み自体を行わない。
    public func removeAll(_ urls: [URL]) {
        let removed = Set(urls.map(\.normalizedPathKey))
        guard !removed.isEmpty else { return }
        let paths = bookmarkedPaths.paths
        let remaining = paths.filter { !removed.contains($0) }
        guard remaining.count != paths.count else { return }
        bookmarkedPaths.replaceAll(with: remaining)
    }

    /// ブックマーク済みの URL を返す(順序は保持しない。表示時にソートする)。
    public func bookmarkedURLs() -> [URL] {
        bookmarkedPaths.urls
    }

    /// rename / move をブックマーク状態に反映する。ブックマークされていなければ何もしない。
    public func noteRenamed(from oldURL: URL, to newURL: URL) {
        bookmarkedPaths.replace(oldURL, with: newURL)
    }
}
