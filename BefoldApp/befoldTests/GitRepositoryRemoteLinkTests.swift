@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 実 git が作ったリポジトリからリモートのリンクを組み立てられること、および
/// 組み立てられない条件で nil へ縮退すること（メニューは disabled になる）。
///
/// URL の形式（ホストごとの組み立て・エンコード・対応外ホスト）は純粋テスト
/// `RemoteForgeTests` が網羅している。ここで実 git に頼るのは、リポジトリから読む値
/// （ブランチ名・origin・作業ツリールート）だけで、リポジトリは 2 つで足りる（TASK-662.6。
/// 以前は 8 件がそれぞれ init・commit・remote add していた）。
struct GitRepositoryRemoteLinkTests {
    private func makeRepo(_ dir: URL, remote: String? = nil) throws {
        GitTestRepo.initRepository(at: dir)
        try GitTestRepo.commitFile(in: dir)
        if let remote { GitTestRepo.run(["remote", "add", "origin", remote], in: dir) }
    }

    private func link(_ url: URL) -> String? {
        GitRepository().remoteFileLink(forFileAt: url)?.url.absoluteString
    }

    /// 未 push のブランチでも「リモートに在るか」を確かめずブランチ名で組み立てる。
    /// ここに判定を足すと、作ったばかりのブランチで項目が黙って無効化される。
    /// サブディレクトリのファイルはリポジトリルート基準の相対パスになる。
    @Test("origin が GitHub なら、未 push のブランチ名とルート基準の相対パスで blob URL を組み立てる")
    func buildsLinkFromRepositoryState() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url, remote: "git@github.com:Tommy109/behold.git")
        GitTestRepo.createBranch(named: "feature/local-only", in: temp.url)
        let nested = try temp.file(atPath: "docs/dev/設計 メモ.md", contents: "x")

        let blob = "https://github.com/Tommy109/behold/blob/feature/local-only"
        #expect(link(temp.url.appendingPathComponent("main.swift")) == "\(blob)/main.swift")
        #expect(link(nested) == "\(blob)/docs/dev/%E8%A8%AD%E8%A8%88%20%E3%83%A1%E3%83%A2.md")
    }

    /// 1 つのリポジトリの状態を順に変えながら、組み立てられない条件をそれぞれ確かめる。
    @Test("origin が無い・対応外のホスト・detached HEAD では nil")
    func returnsNilWhenRepositoryStateCannotBuildLink() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let file = temp.url.appendingPathComponent("main.swift")

        #expect(link(file) == nil, "origin が無い")

        GitTestRepo.run(["remote", "add", "origin", "git@codeberg.org:Tommy109/behold.git"], in: temp.url)
        #expect(link(file) == nil, "対応外のホスト")

        GitTestRepo.run(["remote", "set-url", "origin", "git@github.com:Tommy109/behold.git"], in: temp.url)
        // 前提の確認: ブランチ上なら組み立てられる(nil になるのは detached だからであること)。
        #expect(link(file) != nil)
        GitTestRepo.run(["checkout", "--detach", "HEAD"], in: temp.url)
        #expect(link(file) == nil, "detached HEAD")
    }

    @Test("git 管理外のファイルでは nil")
    func returnsNilOutsideRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }

        #expect(link(temp.url.appendingPathComponent("x.md")) == nil)
    }
}
