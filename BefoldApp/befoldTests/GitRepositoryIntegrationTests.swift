@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 実 git を spawn する Integration テスト。worktree porcelain のパース網羅は
/// `GitRepositoryTests.parsesWorktreeListPorcelain` に任せているため、ここでは
/// 「実 git の出力を実際に解釈できる」ことのスモークに絞る(規約の Unit/Integration 分離基準:
/// 別プロセスの実挙動が結果を左右するテストはここに置く)。
struct GitRepositoryIntegrationTests {
    /// 実 git を叩くテスト用のリポジトリ。git 1 回あたりの予算は他のポーリング待機と同じ
    /// 単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)から採る。少コアの CI で数百テストを
    /// 並行実行すると git の起動自体が遅れうるため、本番既定の 10 秒に縛らず
    /// CI 側から延ばせるようにしておく。
    private func makeRepository() -> GitRepository {
        GitRepository(runner: GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10)))
    }

    private func makeRepo(_ dir: URL) throws {
        GitTestRepo.initRepository(at: dir)
        try GitTestRepo.commitFile(in: dir)
    }

    @Test("root と追跡ファイルを取得する")
    func rootAndTrackedFiles() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = makeRepository()
        let lookup = repo.root(forFileAt: temp.url.appendingPathComponent("main.swift"))
        let root = try #require(lookup.foundRoot)
        #expect(root.standardizedFileURL == temp.url.standardizedFileURL)
        #expect(repo.trackedFiles(at: root)?.map(\.lastPathComponent) == ["main.swift"])
    }

    /// `ls-files -z` を使う理由そのものの検証。既定の改行区切り出力では、スペースや
    /// 引用符を含むファイル名が core.quotepath でエスケープされて壊れる。
    @Test("スペース・引用符を含むファイル名も欠けずに列挙される")
    func trackedFilesHandleSpacesAndQuotesInNames() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let awkwardNames = ["my notes.md", "quote\"name.md", "日本語 メモ.md"]
        for name in awkwardNames {
            try "x".write(to: temp.url.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        GitTestRepo.run(["add", "."], in: temp.url)

        let tracked = makeRepository().trackedFiles(at: temp.url)?.map(\.lastPathComponent)

        for name in awkwardNames {
            #expect(tracked?.contains(name) == true, "\(name) が列挙されていない")
        }
    }

    /// git が動いて「リポジトリではない」と答えた場合と、git を実行できず不明な場合とを
    /// 区別する(キャッシュ層は前者だけを覚えるため、取り違えると失敗が固定化する)。
    @Test("git 管理外は notARepository として返る")
    func reportsNotARepositoryOutsideRepo() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        #expect(makeRepository().root(forFileAt: temp.url.appendingPathComponent("x.md")) == .notARepository)
    }

    @Test("index の更新で fingerprint が変わる")
    func fingerprintChangesOnIndexUpdate() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = makeRepository()
        let before = repo.indexFingerprint(at: temp.url)
        #expect(before != nil)
        try "x".write(to: temp.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        GitTestRepo.run(["add", "b.txt"], in: temp.url)
        let after = repo.indexFingerprint(at: temp.url)
        #expect(after != before)
    }

    @Test("本体リポジトリのラベルは接尾辞なしのディレクトリ名になる")
    func repositoryLabelForMainRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)

        let label = makeRepository().repositoryLabel(forRoot: temp.url)

        #expect(label == temp.url.standardizedFileURL.lastPathComponent)
    }

    @Test("worktree のラベルは本体名とworktreeディレクトリ名を併記する")
    func repositoryLabelForWorktree() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("feature-x")
        GitTestRepo.run(["worktree", "add", worktreeDir.path, "-b", "feature-x"], in: main.url)

        let label = makeRepository().repositoryLabel(forRoot: worktreeDir)

        let mainName = main.url.standardizedFileURL.lastPathComponent
        #expect(label == "\(mainName) (feature-x)")
    }

    @Test("git を実行できない場合はディレクトリ名のみに縮退する")
    func repositoryLabelFallsBackWhenGitUnavailable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = GitRepository(runner: GitCommandRunner(timeout: 0.001))

        let label = repo.repositoryLabel(forRoot: temp.url)

        #expect(label == temp.url.standardizedFileURL.lastPathComponent)
    }

    @Test("本体リポジトリの identity はディレクトリ名と自身のルートを返す")
    func repositoryIdentityForMainRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)

        let identity = makeRepository().repositoryIdentity(forRoot: temp.url)

        #expect(identity.label == temp.url.standardizedFileURL.lastPathComponent)
        #expect(identity.mainRoot.resolvingSymlinksInPath() == temp.url.resolvingSymlinksInPath())
    }

    @Test("worktree の identity は本体ルートを指す")
    func repositoryIdentityForWorktree() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("feature-x")
        GitTestRepo.run(["worktree", "add", worktreeDir.path, "-b", "feature-x"], in: main.url)

        let identity = makeRepository().repositoryIdentity(forRoot: worktreeDir)

        #expect(identity.label == "\(main.url.standardizedFileURL.lastPathComponent) (feature-x)")
        #expect(identity.mainRoot.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
    }

    /// worktree 列挙のパース網羅(ブランチ短縮・detached・並び順)は
    /// `GitRepositoryTests.parsesWorktreeListPorcelain` のインメモリテストが担う。
    /// ここでは「実 git の porcelain 出力を実際に解釈できる」ことだけを、
    /// 本体 + 追加 worktree(ブランチ有り) + worktree 側からの列挙を 1 本で確認する。
    @Test("実 git の worktree 一覧を解釈できる")
    func worktreesReflectRealGitOutput() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        // ディレクトリ名とブランチ名を意図的にずらし、ブランチ側を拾っていることを確かめる。
        let worktreeDir = worktreeParent.url.appendingPathComponent("etc002")
        GitTestRepo.run(["worktree", "add", worktreeDir.path, "-b", "feat/repository"], in: main.url)
        // detached では git が branch 行を出さない。インメモリのフィクスチャが前提にしている
        // この出力形を、実 git の出力に結びつけて固定する。
        let detachedDir = worktreeParent.url.appendingPathComponent("detached-wt")
        GitTestRepo.run(["worktree", "add", "--detach", detachedDir.path], in: main.url)

        let fromMain = makeRepository().worktrees(forRoot: main.url)
        #expect(fromMain.map(\.isMain) == [true, false, false])
        #expect(fromMain.first?.root.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
        #expect(fromMain.first?.branch != nil)

        let branched = fromMain.first { $0.root.resolvingSymlinksInPath() == worktreeDir.resolvingSymlinksInPath() }
        #expect(branched?.branch == "feat/repository")
        #expect(branched?.displayName == "feat/repository (etc002)")

        let detached = fromMain.first { $0.root.resolvingSymlinksInPath() == detachedDir.resolvingSymlinksInPath() }
        #expect(detached?.branch == nil)
        #expect(detached?.displayName == "detached-wt")

        // worktree 側から列挙しても本体が先頭に来る。
        let fromWorktree = makeRepository().worktrees(forRoot: worktreeDir)
        #expect(fromWorktree.map(\.isMain) == [true, false, false])
        #expect(fromWorktree.first?.root.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
    }

    @Test("git を実行できない場合の worktree 一覧は空になる")
    func worktreesFallBackToEmptyWhenGitUnavailable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = GitRepository(runner: GitCommandRunner(timeout: 0.001))

        #expect(repo.worktrees(forRoot: temp.url).isEmpty)
    }
}
