@testable import befold
import Foundation
import Testing

/// リモート URL の解釈とホストごとの URL 組み立て（git を起動しない純関数）。
struct RemoteForgeTests {
    /// SSH 形式と HTTPS 形式は同じ owner/repo になる。`.git` の有無・末尾スラッシュ・
    /// ssh:// 形式も同じ結果に畳む。ここが分かれると「同じリポジトリなのに人によって
    /// 出る URL が違う」形で壊れる。
    @Test(
        "SSH / HTTPS / .git の有無にかかわらず同じホストと owner/repo になる",
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
        let resolved = RemoteForge.resolve(fromRemote: remote)
        #expect(resolved?.forge == .gitHub)
        #expect(resolved?.slug == "Tommy109/behold")
    }

    @Test(
        "対応外のホスト・owner/repo に分解できない形は nil",
        arguments: [
            "git@codeberg.org:Tommy109/behold.git",
            "https://example.com/Tommy109/behold.git",
            "https://github.com/Tommy109",
            "git@github.com:",
            "",
            "not a url",
        ]
    )
    func rejectsUnsupportedRemotes(remote: String) {
        #expect(RemoteForge.resolve(fromRemote: remote) == nil)
    }

    /// ホスト名で解決したホスティングと、そのホスティングの URL 形式が対応していること。
    /// GitHub は `/blob/`、GitLab は `/-/blob/`、Bitbucket は `/src/` と形が違うため、
    /// ここが 1 つにまとまっていると別ホストで嘘のリンクを作る。
    @Test(
        "ホストごとの URL 形式",
        arguments: [
            ("git@github.com:owner/repo.git", RemoteForge.gitHub, "https://github.com/owner/repo/blob/main/a.md"),
            ("git@gitlab.com:owner/repo.git", .gitLab, "https://gitlab.com/owner/repo/-/blob/main/a.md"),
            ("git@bitbucket.org:owner/repo.git", .bitbucket, "https://bitbucket.org/owner/repo/src/main/a.md"),
        ]
    )
    func buildsHostSpecificURL(remote: String, expectedForge: RemoteForge, expectedURL: String) throws {
        let resolved = try #require(RemoteForge.resolve(fromRemote: remote))
        #expect(resolved.forge == expectedForge)
        let url = resolved.forge.blobURL(slug: resolved.slug, branch: "main", relativePath: "a.md")
        #expect(url?.absoluteString == expectedURL)
    }

    /// GitLab はサブグループでパスが 3 段以上になる。2 段で切ると別のリポジトリを指す。
    @Test("GitLab のサブグループは段数を落とさない")
    func keepsGitLabSubgroups() throws {
        let resolved = try #require(RemoteForge.resolve(fromRemote: "git@gitlab.com:group/subgroup/repo.git"))
        #expect(resolved.slug == "group/subgroup/repo")
    }

    /// GitHub / Bitbucket は owner/repo の 2 段しか無い。余分な段が付いた URL
    /// （`https://github.com/owner/repo/tree/main` を貼り付けた等）でも 2 段へ落とす。
    @Test("GitHub は 2 段より深いパスを owner/repo へ落とす")
    func trimsExtraPathComponentsOnGitHub() throws {
        let resolved = try #require(RemoteForge.resolve(fromRemote: "https://github.com/owner/repo/tree/main"))
        #expect(resolved.slug == "owner/repo")
    }

    @Test("表示名は固有名詞のまま")
    func exposesDisplayName() {
        #expect(RemoteForge.gitHub.displayName == "GitHub")
        #expect(RemoteForge.gitLab.displayName == "GitLab")
        #expect(RemoteForge.bitbucket.displayName == "Bitbucket")
    }

    /// 空白や日本語を含むパスは、そのまま並べるとホスト側が解決できない URL になる。
    /// パス区切りの `/` は潰さずに残ることも同時に固定する。
    @Test("空白・日本語を含むパスはパーセントエンコードされ、区切りの / は残る")
    func escapesPathComponents() {
        let url = RemoteForge.gitHub.blobURL(
            slug: "Tommy109/behold", branch: "main", relativePath: "docs/日本語 メモ.md"
        )
        #expect(url?.absoluteString
            == "https://github.com/Tommy109/behold/blob/main/docs/%E6%97%A5%E6%9C%AC%E8%AA%9E%20%E3%83%A1%E3%83%A2.md")
    }

    /// スラッシュを含むブランチ名（`feature/x`）は分割せずそのまま並ぶ。
    @Test("スラッシュを含むブランチ名もそのまま並ぶ")
    func keepsSlashesInBranchName() {
        let url = RemoteForge.gitHub.blobURL(
            slug: "Tommy109/behold", branch: "feature/remote-link", relativePath: "README.md"
        )
        #expect(url?.absoluteString == "https://github.com/Tommy109/behold/blob/feature/remote-link/README.md")
    }

    @Test("要素が欠けていれば URL は作らない")
    func rejectsEmptyComponents() {
        #expect(RemoteForge.gitHub.blobURL(slug: "", branch: "main", relativePath: "a.md") == nil)
        #expect(RemoteForge.gitHub.blobURL(slug: "o/r", branch: "", relativePath: "a.md") == nil)
        #expect(RemoteForge.gitHub.blobURL(slug: "o/r", branch: "main", relativePath: "") == nil)
    }
}
