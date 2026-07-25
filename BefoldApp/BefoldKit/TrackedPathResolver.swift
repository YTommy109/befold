import Foundation

/// url を含む git リポジトリの追跡ファイル絶対 URL 一覧を返す。git 管理外なら nil。
public protocol GitFileIndexing: Sendable {
    func trackedFiles(forFileAt url: URL) -> [URL]?
}

/// パス参照の解決結果。
public enum ResolvedReference: Equatable, Sendable {
    case external(URL) // http/https。リンク維持(ブラウザで開く)
    case resolved(URL) // 実在を確認できたローカルファイル
    case unresolved // ローカルパスだが解決できなかった(リンクにしない)
    case ignored // 空 / #anchor / 未対応スキーム(据え置き)
}

/// 「相対/絶対で実在 → git 追跡ファイルへの構成要素サフィックス一致(近さ最小)」の順で
/// パス参照を解決する。表示時(リンク化判定)とクリック時(オープン)の両方から使う単一情報源。
public struct TrackedPathResolver: Sendable {
    private let fileReader: FileReading
    private let gitIndex: GitFileIndexing

    public init(fileReader: FileReading = DefaultFileReader(), gitIndex: GitFileIndexing) {
        self.fileReader = fileReader
        self.gitIndex = gitIndex
    }

    public func resolve(href: String, baseURL: URL) -> ResolvedReference {
        switch ReferenceResolver.resolve(href: href, baseURL: baseURL) {
        case let .external(url):
            return .external(url)
        case .unsupported:
            return .ignored
        case let .localFile(url):
            if fileReader.isExistingFile(at: url) {
                return .resolved(url)
            }
            guard let written = ReferenceResolver.localPathString(from: href),
                  let candidates = gitIndex.trackedFiles(forFileAt: baseURL),
                  let match = SuffixPathMatcher.bestMatch(
                      writtenPath: written, candidates: candidates, baseURL: baseURL
                  )
            else { return .unresolved }
            return .resolved(match)
        }
    }
}
