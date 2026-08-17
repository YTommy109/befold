import Foundation

/// リモートを Web で見せるホスティング 1 つ（GitHub / GitLab / Bitbucket）。
///
/// リモート URL の解釈とファイルを指す URL の組み立てを、ホストごとの差ごとここへ集める。
/// 分けると「どのホストに対応しているか」を数える場所が増え、メニュー文言・URL 形式・
/// 判定のどれかだけが増えるずれ方をする。
///
/// **permalink（コミット SHA 固定）は作らない。** 用途が「いま開いている資料の最新版を
/// 他人や AI に渡す」ことなので、ブランチ名で指す。行番号付き引用のように permalink が
/// 効く場面は befold にまだ無い。
///
/// 自建て（GitHub Enterprise / self-managed GitLab）は判別できないため対象外。
/// ホスト名だけでは形式を決められず、推測すると別のホストの URL 形式で嘘のリンクを作る。
enum RemoteForge: CaseIterable, Sendable {
    case gitHub
    case gitLab
    case bitbucket

    /// リモート URL のホスト名。ここに一致したものだけを扱う。
    var host: String {
        switch self {
        case .gitHub: "github.com"
        case .gitLab: "gitlab.com"
        case .bitbucket: "bitbucket.org"
        }
    }

    /// メニュー文言へ差し込む表示名。翻訳しない固有名詞。
    var displayName: String {
        switch self {
        case .gitHub: "GitHub"
        case .gitLab: "GitLab"
        case .bitbucket: "Bitbucket"
        }
    }

    /// リポジトリ配下のファイルを指す URL のパス部分。ホストごとに違う
    /// （GitHub は `/blob/`、GitLab は `/-/blob/`、Bitbucket は `/src/`）。
    private func blobPath(slug: String, branch: String, relativePath: String) -> String {
        switch self {
        case .gitHub: "/\(slug)/blob/\(branch)/\(relativePath)"
        case .gitLab: "/\(slug)/-/blob/\(branch)/\(relativePath)"
        case .bitbucket: "/\(slug)/src/\(branch)/\(relativePath)"
        }
    }

    /// リポジトリを指す識別子（`owner/repo`）に許す段数。
    /// GitLab だけサブグループで 3 段以上になりうる。
    private var allowsNestedNamespace: Bool {
        self == .gitLab
    }

    /// リモート URL 文字列から、対応しているホストとリポジトリ識別子を取り出す。
    /// 対応外のホストや `owner/repo` に分解できない形は nil（呼び出し側はメニューを無効化する）。
    ///
    /// 受け付ける形:
    /// - `git@github.com:owner/repo.git`（scp 風。URL ではないので自前で分ける）
    /// - `ssh://git@github.com/owner/repo.git` / `https://` / `http://` / `git://`
    ///
    /// `.git` の有無と末尾スラッシュの有無で結果が変わらないことを `RemoteForgeTests` が固定する。
    static func resolve(fromRemote remote: String) -> (forge: RemoteForge, slug: String)? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (host, path) = hostAndPath(ofRemote: trimmed) else { return nil }
        let lowercasedHost = host.lowercased()
        guard let forge = allCases.first(where: { $0.host == lowercasedHost }) else { return nil }
        guard let slug = forge.slug(fromPath: path) else { return nil }
        return (forge, slug)
    }

    /// リモート URL のパス部分からリポジトリ識別子を作る。`.git` と余分な段は落とす。
    private func slug(fromPath path: String) -> String? {
        var components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        if !allowsNestedNamespace { components = Array(components.prefix(2)) }
        if components[components.count - 1].hasSuffix(".git") {
            components[components.count - 1].removeLast(".git".count)
        }
        guard components.allSatisfy({ !$0.isEmpty }) else { return nil }
        return components.joined(separator: "/")
    }

    /// `https://{host}/{slug}/…/{branch}/{relativePath}` を組み立てる。
    ///
    /// エスケープは `URLComponents` に任せる（空白・日本語を含むパスをそのまま渡すと
    /// パーセントエンコードされた URL になる）。手で `addingPercentEncoding` を書くと
    /// `/` まで潰すかどうかを毎回間違える。
    func blobURL(slug: String, branch: String, relativePath: String) -> URL? {
        guard !slug.isEmpty, !branch.isEmpty, !relativePath.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = blobPath(slug: slug, branch: branch, relativePath: relativePath)
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
