@testable import befold
import BefoldTestSupport
import Foundation
import Testing

struct GitRepositoryTests {
    /// 実 git を叩くテスト用のリポジトリ。git 1 回あたりの予算は他のポーリング待機と同じ
    /// 単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)から採る。少コアの CI で数百テストを
    /// 並行実行すると git の起動自体が遅れうるため、本番既定の 10 秒に縛らず
    /// CI 側から延ばせるようにしておく。
    private func makeRepository() -> GitRepository {
        GitRepository(runner: GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10)))
    }

    private func git(_ dir: URL, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", dir.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func makeRepo(_ dir: URL) throws {
        git(dir, ["init"])
        git(dir, ["config", "user.email", "t@example.com"])
        git(dir, ["config", "user.name", "t"])
        try "print(1)".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        git(dir, ["add", "main.swift"])
        git(dir, ["commit", "-m", "init"])
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
        git(temp.url, ["add", "."])

        let tracked = makeRepository().trackedFiles(at: temp.url)?.map(\.lastPathComponent)

        for name in awkwardNames {
            #expect(tracked?.contains(name) == true, "\(name) が列挙されていない")
        }
    }

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
        git(temp.url, ["add", "b.txt"])
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
        git(main.url, ["worktree", "add", worktreeDir.path, "-b", "feature-x"])

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
        git(main.url, ["worktree", "add", worktreeDir.path, "-b", "feature-x"])

        let identity = makeRepository().repositoryIdentity(forRoot: worktreeDir)

        #expect(identity.label == "\(main.url.standardizedFileURL.lastPathComponent) (feature-x)")
        #expect(identity.mainRoot.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
    }

    @Test("worktree の無いリポジトリでは本体 1 件だけが返る")
    func worktreesForMainOnlyRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)

        let worktrees = makeRepository().worktrees(forRoot: temp.url)

        #expect(worktrees.count == 1)
        #expect(worktrees.first?.isMain == true)
        #expect(worktrees.first?.root.resolvingSymlinksInPath() == temp.url.resolvingSymlinksInPath())
    }

    @Test("worktree を追加すると本体と worktree が区別されて列挙される")
    func worktreesIncludeAddedWorktree() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("feature-x")
        git(main.url, ["worktree", "add", worktreeDir.path, "-b", "feature-x"])

        let worktrees = makeRepository().worktrees(forRoot: main.url)

        #expect(worktrees.count == 2)
        #expect(worktrees.first?.isMain == true)
        #expect(worktrees.first?.root.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
        #expect(worktrees.last?.isMain == false)
        #expect(worktrees.last?.root.resolvingSymlinksInPath() == worktreeDir.resolvingSymlinksInPath())
    }

    @Test("列挙結果はチェックアウト中のブランチ名を短縮形で持つ")
    func worktreesCarryShortBranchNames() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        // ディレクトリ名とブランチ名を意図的にずらし、ブランチ側を拾っていることを確かめる。
        let worktreeDir = worktreeParent.url.appendingPathComponent("etc002")
        git(main.url, ["worktree", "add", worktreeDir.path, "-b", "feat/repository"])

        let worktrees = makeRepository().worktrees(forRoot: main.url)

        #expect(worktrees.last?.branch == "feat/repository")
        #expect(worktrees.last?.displayName == "feat/repository (etc002)")
        // 本体側もブランチ名を持つ(既定ブランチ名は環境依存なので nil でないことだけ見る)。
        #expect(worktrees.first?.branch != nil)
    }

    @Test("detached HEAD の worktree はディレクトリ名だけで表示する")
    func detachedWorktreeFallsBackToDirectoryName() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("detached-wt")
        git(main.url, ["worktree", "add", "--detach", worktreeDir.path])

        let worktrees = makeRepository().worktrees(forRoot: main.url)

        #expect(worktrees.last?.branch == nil)
        #expect(worktrees.last?.displayName == "detached-wt")
    }

    @Test("worktree 側から列挙しても本体が先頭に来る")
    func worktreesEnumeratedFromWorktreeStartWithMain() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("feature-x")
        git(main.url, ["worktree", "add", worktreeDir.path, "-b", "feature-x"])

        let worktrees = makeRepository().worktrees(forRoot: worktreeDir)

        #expect(worktrees.map(\.isMain) == [true, false])
        #expect(worktrees.first?.root.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
    }

    @Test("git を実行できない場合の worktree 一覧は空になる")
    func worktreesFallBackToEmptyWhenGitUnavailable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = GitRepository(runner: GitCommandRunner(timeout: 0.001))

        #expect(repo.worktrees(forRoot: temp.url).isEmpty)
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
