import Foundation

/// リモート URL とブランチ・相対パスから GitHub の blob URL を組み立てる純粋ロジック。
///
/// git を一切触らないのは、組み立ての規則（SSH 形式と HTTPS 形式の正規化、パスの
/// エスケープ）をリポジトリを用意せずにテストできるようにするため。git 側から値を
/// 取る処理は `GitRepository.gitHubBlobURL(forFileAt:)` が持つ。
///
/// **permalink（コミット SHA 固定）は作らない。** 用途が「いま開いている資料の最新版を
/// 他人や AI に渡す」ことなので、ブランチ名で指す。行番号付き引用のように permalink が
/// 効く場面は befold にまだ無い。
enum GitHubFileLink {
    /// GitHub の Web ホスト。SSH 形式・HTTPS 形式のどちらから来ても、組み立て先はここ。
    private static let host = "github.com"

    /// リモート URL 文字列から `owner/repo` を取り出す。GitHub 以外のホストや
    /// owner/repo に分解できない形は nil（呼び出し側はメニューを無効化する）。
    ///
    /// 受け付ける形:
    /// - `git@github.com:owner/repo.git`（scp 風。URL ではないので自前で分ける）
    /// - `ssh://git@github.com/owner/repo.git` / `https://` / `http://` / `git://`
    ///
    /// `.git` の有無と末尾スラッシュの有無で結果が変わらないことを
    /// `GitHubFileLinkTests` が固定する。
    static func repositorySlug(fromRemote remote: String) -> String? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (host, path) = hostAndPath(ofRemote: trimmed) else { return nil }
        guard host.lowercased() == Self.host else { return nil }
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        let owner = components[0]
        var repository = components[1]
        if repository.hasSuffix(".git") { repository.removeLast(".git".count) }
        guard !owner.isEmpty, !repository.isEmpty else { return nil }
        return "\(owner)/\(repository)"
    }

    /// `https://github.com/{slug}/blob/{branch}/{relativePath}` を組み立てる。
    ///
    /// エスケープは `URLComponents` に任せる（空白・日本語を含むパスをそのまま渡すと
    /// パーセントエンコードされた URL になる）。手で `addingPercentEncoding` を書くと
    /// `/` まで潰すかどうかを毎回間違える。
    static func blobURL(slug: String, branch: String, relativePath: String) -> URL? {
        guard !slug.isEmpty, !branch.isEmpty, !relativePath.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/\(slug)/blob/\(branch)/\(relativePath)"
        return components.url
    }

    /// リモート URL をホストとパスに分ける。scp 風（`git@host:path`）は URL として
    /// 解釈できないため、スキーム付きかどうかで経路を分ける。
    private static func hostAndPath(ofRemote remote: String) -> (host: String, path: String)? {
        if remote.contains("://") {
            guard let components = URLComponents(string: remote), let host = components.host else { return nil }
            return (host, components.path)
        }
        // scp 風。`user@host:path` の最初の `:` より前がホスト部（ユーザー名を含みうる）。
        guard let colon = remote.firstIndex(of: ":") else { return nil }
        let hostPart = String(remote[remote.startIndex ..< colon])
        let path = String(remote[remote.index(after: colon)...])
        let host = hostPart.contains("@") ? String(hostPart.split(separator: "@").last ?? "") : hostPart
        guard !host.isEmpty else { return nil }
        return (host, path)
    }
}
