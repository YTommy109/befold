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

    /// ブックマーク済みの URL を返す(順序は保持しない。表示時にソートする)。
    public func bookmarkedURLs() -> [URL] {
        bookmarkedPaths.urls
    }

    /// rename / move をブックマーク状態に反映する。ブックマークされていなければ何もしない。
    public func noteRenamed(from oldURL: URL, to newURL: URL) {
        bookmarkedPaths.replace(oldURL, with: newURL)
    }
}
