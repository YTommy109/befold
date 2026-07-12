import Foundation

/// パスをコピーする際に絶対パスではなく相対パスにするための純粋ロジック。
public enum PathRelativizer {
    /// `url` を `base` からの相対パス文字列にする。
    /// `url` が `base` の外にある場合は `url.path`（絶対パス）にフォールバックする。
    public static func relativePath(of url: URL, relativeTo base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.starts(with: baseComponents) else {
            return url.path
        }
        return urlComponents.dropFirst(baseComponents.count).joined(separator: "/")
    }
}
