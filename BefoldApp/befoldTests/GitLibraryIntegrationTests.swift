@testable import befold
import BefoldTestSupport
import Foundation
import libgit2
import Testing

/// 実 git が作ったリポジトリを libgit2 が開けることのスモーク。
///
/// `GitLibraryTests` のフィクスチャは `.git/` を手で組み立てるため、実 git が書く
/// index のバージョンや refs の形（packed-refs 等）を通っていない。同梱の libgit2 が
/// 手元の git 2.x の生成物を読めることは、ここでしか確かめられない。
struct GitLibraryIntegrationTests {
    @Test("実 git のリポジトリを開いて作業ツリーのパスを取れる")
    func opensRepositoryCreatedByRealGit() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        GitTestRepo.initRepository(at: tmp.url)
        try GitTestRepo.commitFile(in: tmp.url)

        let workdir = GitLibrary.withRepository(at: tmp.url) { repository -> String? in
            git_repository_workdir(repository).map { String(cString: $0) }
        }
        // libgit2 が返すパスはシンボリックリンクを解決しない。一時ディレクトリは
        // /var -> /private/var のリンク越しに作られるため、両辺を解決して比べる。
        let path = try #require(try workdir.get())
        let actual = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        #expect(actual == tmp.url.resolvingSymlinksInPath())
    }

    /// 作業ツリー内のファイルを渡しても、親方向へ探索してリポジトリが見つかること
    /// （`git rev-parse --show-toplevel` と同じ振る舞い）。
    @Test("作業ツリー内のファイルパスからでもリポジトリを開ける")
    func opensRepositoryFromNestedFilePath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        GitTestRepo.initRepository(at: tmp.url)
        try GitTestRepo.commitFile(in: tmp.url)
        let nested = try tmp.file(atPath: "sub/note.md", contents: "# note\n")

        let opened = GitLibrary.withRepository(at: nested) { _ in true }
        #expect(opened == .success(true))
    }
}
