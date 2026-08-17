@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 実 git が作ったリポジトリからリモートのリンクを組み立てられること、および
/// 組み立てられない条件で nil へ縮退すること（メニューは disabled になる）。
struct GitRepositoryRemoteLinkTests {
    private func makeRepo(_ dir: URL, remote: String? = nil) throws {
        GitTestRepo.initRepository(at: dir)
        try GitTestRepo.commitFile(in: dir)
        if let remote { GitTestRepo.run(["remote", "add", "origin", remote], in: dir) }
    }

    @Test("origin が GitHub なら GitHub の blob URL を組み立てる")
    func buildsLinkForGitHubOrigin() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url, remote: "git@github.com:Tommy109/behold.git")

        let link = GitRepository().remoteFileLink(forFileAt: temp.url.appendingPathComponent("main.swift"))
        let branch = try #require(GitRepository().worktrees(forRoot: temp.url).first?.branch)

        #expect(link?.url.absoluteString == "https://github.com/Tommy109/behold/blob/\(branch)/main.swift")
    }

    /// 未 push のブランチでも「リモートに在るか」を確かめずブランチ名で組み立てる。
    /// ここに判定を足すと、作ったばかりのブランチで項目が黙って無効化される。
    @Test("未 push のブランチでもブランチ名のまま URL を作る")
    func buildsLinkForUnpushedBranch() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url, remote: "https://github.com/Tommy109/behold.git")
        GitTestRepo.createBranch(named: "feature/local-only", in: temp.url)

        let link = GitRepository().remoteFileLink(forFileAt: temp.url.appendingPathComponent("main.swift"))

        #expect(link?.url.absoluteString
            == "https://github.com/Tommy109/behold/blob/feature/local-only/main.swift")
    }

    @Test("サブディレクトリのファイルはリポジトリルート基準の相対パスになる")
    func usesRepositoryRootRelativePath() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url, remote: "git@github.com:Tommy109/behold.git")
        let nested = temp.url.appendingPathComponent("docs/dev", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "x".write(to: nested.appendingPathComponent("設計 メモ.md"), atomically: true, encoding: .utf8)

        let link = GitRepository().remoteFileLink(forFileAt: nested.appendingPathComponent("設計 メモ.md"))

        #expect(link?.url.absoluteString.hasPrefix("https://github.com/Tommy109/behold/blob/") == true)
        #expect(link?.url.absoluteString.hasSuffix("/docs/dev/%E8%A8%AD%E8%A8%88%20%E3%83%A1%E3%83%A2.md") == true)
    }

    @Test("origin が無いリポジトリでは nil")
    func returnsNilWithoutOrigin() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)

        #expect(GitRepository().remoteFileLink(forFileAt: temp.url.appendingPathComponent("main.swift")) == nil)
    }

    @Test("対応外のホストのリモートでは nil")
    func returnsNilForUnsupportedRemote() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url, remote: "git@codeberg.org:Tommy109/behold.git")

        #expect(GitRepository().remoteFileLink(forFileAt: temp.url.appendingPathComponent("main.swift")) == nil)
    }

    @Test("detached HEAD では nil")
    func returnsNilForDetachedHead() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url, remote: "git@github.com:Tommy109/behold.git")
        GitTestRepo.run(["checkout", "--detach", "HEAD"], in: temp.url)

        #expect(GitRepository().remoteFileLink(forFileAt: temp.url.appendingPathComponent("main.swift")) == nil)
    }

    @Test("git 管理外のファイルでは nil")
    func returnsNilOutsideRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }

        #expect(GitRepository().remoteFileLink(forFileAt: temp.url.appendingPathComponent("x.md")) == nil)
    }

    /// ホストが変われば URL 形式も変わることを、実リポジトリ経由でも 1 本だけ固定する
    /// （形式そのものの網羅は `RemoteForgeTests`）。
    @Test("origin が GitLab なら GitLab の URL 形式になる")
    func buildsLinkForGitLabOrigin() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url, remote: "git@gitlab.com:group/subgroup/behold.git")

        let link = GitRepository().remoteFileLink(forFileAt: temp.url.appendingPathComponent("main.swift"))
        let branch = try #require(GitRepository().worktrees(forRoot: temp.url).first?.branch)

        #expect(link?.forge == .gitLab)
        #expect(link?.url.absoluteString
            == "https://gitlab.com/group/subgroup/behold/-/blob/\(branch)/main.swift")
    }
}
