import Foundation
import libgit2

/// ファイルを指す GitHub リンクの解決。`GitRepository` 本体から切り出しているのは、
/// git の読み取り一般ではなく「サイドバーのメニュー 1 項目のための組み立て」だから。
extension GitRepository {
    /// origin の名前。GitHub リンクはこのリモートだけを見る。
    private static let originRemoteName = "origin"

    /// `url` が指すファイルの GitHub blob URL。作れなければ nil。
    ///
    /// nil に畳む理由は区別しない（git 管理外 / libgit2 で開けない / origin が無い /
    /// GitHub 以外のリモート / detached HEAD）。呼び出し側の扱いはどれも「メニュー項目を
    /// 無効化する」で同じで、畳んだ値から理由を作ると型が持っていない情報を騙ることになる
    /// （`GitLibrary.OpenFailure` が `.unusable` の 1 値へ畳んでいるのと同じ判断）。
    ///
    /// **リモートに存在するかは確かめない。** 未 push のブランチでもブランチ名のまま返す
    /// （push すればリンクは生きるので、一時的に 404 になるだけ）。この「判定を足さない」
    /// ことは `GitRepositoryGitHubLinkTests` が固定する。
    ///
    /// 同期に libgit2 を開くため、**一覧の行ごとに呼ばない**こと。呼び出しは右クリックで
    /// メニューを組み立てる時点の 1 回に限る（`SidebarContextMenu`）。
    func gitHubBlobURL(forFileAt url: URL) -> URL? {
        let outcome = GitLibrary.withRepository(at: url.deletingLastPathComponent()) { repository -> URL? in
            guard let workdir = Self.workdirURL(of: repository),
                  let branch = Self.branchName(of: repository),
                  let remote = Self.remoteURL(of: repository, named: Self.originRemoteName),
                  let slug = GitHubFileLink.repositorySlug(fromRemote: remote),
                  let relativePath = Self.relativePath(of: url, inWorkdir: workdir)
            else { return nil }
            return GitHubFileLink.blobURL(slug: slug, branch: branch, relativePath: relativePath)
        }
        return (try? outcome.get()) ?? nil
    }

    /// 名前付きリモートの URL。リモートが無ければ nil。
    private static func remoteURL(of repository: OpaquePointer, named name: String) -> String? {
        var remote: OpaquePointer?
        guard git_remote_lookup(&remote, repository, name) == 0, let remote else { return nil }
        defer { git_remote_free(remote) }
        guard let url = git_remote_url(remote) else { return nil }
        let string = String(cString: url)
        return string.isEmpty ? nil : string
    }

    /// 作業ツリールートからの相対パス。ルートの外にあるファイルは nil。
    ///
    /// `PathRelativizer.relativePath(of:relativeTo:)` を使わないのは、あちらが範囲外の
    /// ファイルで絶対パスへフォールバックするため。ここで絶対パスを受け取ると、
    /// そのまま GitHub の URL に埋まって嘘のリンクになる。
    private static func relativePath(of url: URL, inWorkdir workdir: URL) -> String? {
        let base = workdir.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let target = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard target.count > base.count, target.starts(with: base) else { return nil }
        return target.dropFirst(base.count).joined(separator: "/")
    }
}
