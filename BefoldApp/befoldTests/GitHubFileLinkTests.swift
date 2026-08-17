@testable import befold
import Foundation
import Testing

/// リモート URL の正規化と blob URL の組み立て（git を起動しない純関数）。
struct GitHubFileLinkTests {
    /// SSH 形式と HTTPS 形式は同じ owner/repo になる。`.git` の有無・末尾スラッシュ・
    /// ssh:// 形式も同じ結果に畳む。ここが分かれると「同じリポジトリなのに人によって
    /// 出る URL が違う」形で壊れる。
    @Test(
        "SSH / HTTPS / .git の有無にかかわらず同じ owner/repo になる",
        arguments: [
            "git@github.com:Tommy109/behold.git",
            "git@github.com:Tommy109/behold",
            "ssh://git@github.com/Tommy109/behold.git",
            "https://github.com/Tommy109/behold.git",
            "https://github.com/Tommy109/behold",
            "https://github.com/Tommy109/behold/",
            "git://github.com/Tommy109/behold.git",
            "  https://github.com/Tommy109/behold.git\n",
        ]
    )
    func normalizesRemoteForms(remote: String) {
        #expect(GitHubFileLink.repositorySlug(fromRemote: remote) == "Tommy109/behold")
    }

    @Test(
        "GitHub 以外・owner/repo に分解できない形は nil",
        arguments: [
            "git@gitlab.com:Tommy109/behold.git",
            "https://example.com/Tommy109/behold.git",
            "https://github.com/Tommy109",
            "git@github.com:",
            "",
            "not a url",
        ]
    )
    func rejectsNonGitHubRemotes(remote: String) {
        #expect(GitHubFileLink.repositorySlug(fromRemote: remote) == nil)
    }

    @Test("blob URL はブランチ名と相対パスをそのまま並べる")
    func buildsBlobURL() {
        let url = GitHubFileLink.blobURL(
            slug: "Tommy109/behold", branch: "main", relativePath: "docs/dev/native-app-design.md"
        )
        #expect(url?.absoluteString == "https://github.com/Tommy109/behold/blob/main/docs/dev/native-app-design.md")
    }

    /// 空白や日本語を含むパスは、そのまま並べると GitHub が解決できない URL になる。
    /// パス区切りの `/` は潰さずに残ることも同時に固定する。
    @Test("空白・日本語を含むパスはパーセントエンコードされ、区切りの / は残る")
    func escapesPathComponents() {
        let url = GitHubFileLink.blobURL(
            slug: "Tommy109/behold", branch: "main", relativePath: "docs/日本語 メモ.md"
        )
        #expect(url?
            .absoluteString ==
            "https://github.com/Tommy109/behold/blob/main/docs/%E6%97%A5%E6%9C%AC%E8%AA%9E%20%E3%83%A1%E3%83%A2.md")
    }

    /// スラッシュを含むブランチ名（`feature/x`）は分割せずそのまま並ぶ。
    @Test("スラッシュを含むブランチ名もそのまま並ぶ")
    func keepsSlashesInBranchName() {
        let url = GitHubFileLink.blobURL(
            slug: "Tommy109/behold", branch: "feature/github-link", relativePath: "README.md"
        )
        #expect(url?.absoluteString == "https://github.com/Tommy109/behold/blob/feature/github-link/README.md")
    }

    @Test("要素が欠けていれば URL は作らない")
    func rejectsEmptyComponents() {
        #expect(GitHubFileLink.blobURL(slug: "", branch: "main", relativePath: "a.md") == nil)
        #expect(GitHubFileLink.blobURL(slug: "o/r", branch: "", relativePath: "a.md") == nil)
        #expect(GitHubFileLink.blobURL(slug: "o/r", branch: "main", relativePath: "") == nil)
    }
}
