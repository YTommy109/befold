@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 実 git を起動しない `GitRepository` の unit テスト。
///
/// libgit2 化で「git の出力テキストをパースする純関数」が無くなったため、worktree 列挙の
/// 網羅は実 git フィクスチャの `GitRepositoryIntegrationTests` が担う。ここに残るのは
/// リポジトリを開けなかったときの縮退と、gitdir 解決(ファイル操作のみ)の 2 系統。
struct GitRepositoryTests {
    /// gitdir 解決系のテストが呼ぶ `indexFingerprint` はファイル stat のみで
    /// リポジトリを開かないため、既定生成で足りる。
    private func makeRepository() -> GitRepository {
        GitRepository()
    }

    // MARK: - 開けないリポジトリでの縮退

    /// 「libgit2 が開けないリポジトリ」を作る。実 git を起動せず `.git/` を手で組むため、
    /// 縮退の検証が git のバージョンや壁時計(タイムアウト)に左右されない。
    /// フィクスチャの中身は `GitLibraryTests` と共有する(同じ失敗を 2 通りに定義しない)。
    private func makeUnopenableRepository(in directory: URL) throws {
        try GitLibraryTests.makeUnopenableRepository(in: directory, extensionEntry: "partialclone = origin")
    }

    @Test("リポジトリを開けない場合の root 検出は「不明」であって「管理外」ではない")
    func rootLookupIsUndeterminedWhenRepositoryUnopenable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeUnopenableRepository(in: temp.url)

        let lookup = makeRepository().root(forFileAt: temp.url.appendingPathComponent("main.swift"))

        // ここが .notARepository に倒れると、開けなかっただけの結果が
        // GitCommandFileIndex にキャッシュされ「git 管理外」としてアプリ寿命の間固定される。
        #expect(lookup == .undetermined)
    }

    /// 上のテストと対で「確定した答え」側を固定する。両方が同じ値になっていたら、
    /// キャッシュしてよい/いけないの区別が失われている。
    @Test("git 管理外のディレクトリは「管理外」として確定する")
    func rootLookupIsNotARepositoryOutsideRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }

        #expect(makeRepository().root(forFileAt: temp.url.appendingPathComponent("x.md")) == .notARepository)
    }

    @Test("リポジトリを開けない場合の worktree 一覧は空になる")
    func worktreesFallBackToEmptyWhenRepositoryUnopenable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeUnopenableRepository(in: temp.url)

        #expect(makeRepository().worktrees(forRoot: temp.url).isEmpty)
    }

    @Test("リポジトリを開けない場合はディレクトリ名のみに縮退する")
    func repositoryIdentityFallsBackWhenRepositoryUnopenable() throws {
        let temp = try TempDir(prefix: "any-repository")
        defer { withExtendedLifetime(temp) {} }
        try makeUnopenableRepository(in: temp.url)

        let identity = makeRepository().repositoryIdentity(forRoot: temp.url)

        // ラベルだけだと本体リポジトリの正常系と同じ値になり、開けてしまっても通る。
        // mainRoot まで見て「自身のルートへ縮退した」ことを固定する。
        #expect(identity.label == temp.url.standardizedFileURL.lastPathComponent)
        #expect(identity.mainRoot == temp.url.standardizedFileURL)
    }

    @Test("リポジトリを開けない場合の追跡ファイル一覧は nil(0 件ではない)")
    func trackedFilesAreNilWhenRepositoryUnopenable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeUnopenableRepository(in: temp.url)

        #expect(makeRepository().trackedFiles(at: temp.url) == nil)
    }

    // MARK: - gitdir 解決

    /// submodule の `.git` ファイルは `gitdir: ../.git/modules/<name>` のように
    /// 相対パスを書く。worktree(絶対パス)の分岐しか通っていないと、submodule では
    /// 存在しない index を見て fingerprint が nil になり、キャッシュ無効化が効かなくなる。
    @Test("submodule 形式の相対 gitdir を辿って index を見る")
    func resolvesRelativeGitdirFile() throws {
        let parent = try TempDir()
        defer { withExtendedLifetime(parent) {} }
        let realGitDir = parent.url.appendingPathComponent(".git/modules/sub")
        try FileManager.default.createDirectory(at: realGitDir, withIntermediateDirectories: true)
        try "".write(to: realGitDir.appendingPathComponent("index"), atomically: true, encoding: .utf8)
        let work = parent.url.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try "gitdir: ../.git/modules/sub\n".write(
            to: work.appendingPathComponent(".git"), atomically: true, encoding: .utf8
        )

        #expect(makeRepository().indexFingerprint(at: work) != nil, "相対 gitdir を辿れていない")
    }

    @Test("worktree 形式の .git ファイルは gitdir を辿って index を見る")
    func resolvesWorktreeGitFile() throws {
        let gitdir = try TempDir() // 実 gitdir 相当
        defer { withExtendedLifetime(gitdir) {} }
        let indexURL = gitdir.url.appendingPathComponent("index")
        try "".write(to: indexURL, atomically: true, encoding: .utf8)
        let work = try TempDir()
        defer { withExtendedLifetime(work) {} }
        try "gitdir: \(gitdir.url.path)\n".write(
            to: work.url.appendingPathComponent(".git"), atomically: true, encoding: .utf8
        )
        let fingerprint = makeRepository().indexFingerprint(at: work.url)
        let attributes = try FileManager.default.attributesOfItem(atPath: indexURL.path)
        let expected = attributes[.modificationDate] as? Date
        #expect(fingerprint != nil)
        #expect(fingerprint == expected)
    }
}
