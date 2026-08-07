@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 実 git を要しない unit テスト。worktree porcelain パースは実 git の出力を経ずに
/// インメモリのフィクスチャで網羅する(実 git を通す検証は `GitRepositoryIntegrationTests` の
/// スモーク 1 本に任せる)。gitdir 解決系は実ファイルシステム操作のみでプロセスは起動しない。
struct GitRepositoryTests {
    /// gitdir 解決系のテスト(resolvesRelativeGitdirFile / resolvesWorktreeGitFile)が
    /// 呼ぶ `indexFingerprint` はファイル stat のみで git を起動しないため、既定生成で足りる。
    private func makeRepository() -> GitRepository {
        GitRepository()
    }

    /// git を一度も起動せず、常に「実行できなかった」を返すランナー。
    ///
    /// 縮退の検証を実 git の予算(タイムアウト)で作らないための注入点。予算を極小にする
    /// 方式は git が予算内に終われば普通に成功してしまい、結論が壁時計に左右される
    /// (CI の TSan ジョブで実際に worktree 一覧が返って落ちた)。
    private struct UnavailableGitCommandRunner: GitCommandRunning {
        func run(_: [String], in _: URL?) -> GitCommandOutcome {
            .unavailable
        }
    }

    @Test("git を実行できない場合の worktree 一覧は空になる")
    func worktreesFallBackToEmptyWhenGitUnavailable() {
        let repo = GitRepository(runner: UnavailableGitCommandRunner())

        #expect(repo.worktrees(forRoot: URL(fileURLWithPath: "/tmp/any", isDirectory: true)).isEmpty)
    }

    @Test("git を実行できない場合はディレクトリ名のみに縮退する")
    func repositoryIdentityFallsBackWhenGitUnavailable() {
        let root = URL(fileURLWithPath: "/tmp/any-repository", isDirectory: true)
        let repo = GitRepository(runner: UnavailableGitCommandRunner())

        let identity = repo.repositoryIdentity(forRoot: root)

        // ラベルだけだと本体リポジトリの正常系と同じ値になり、git が動いてしまっても
        // 通ってしまう。mainRoot まで見て「自身のルートへ縮退した」ことを固定する。
        #expect(identity.label == "any-repository")
        #expect(identity.mainRoot == root.standardizedFileURL)
    }

    @Test("git を実行できない場合の root 検出は「不明」であって「管理外」ではない")
    func rootLookupIsUndeterminedWhenGitUnavailable() {
        let repo = GitRepository(runner: UnavailableGitCommandRunner())

        let lookup = repo.root(forFileAt: URL(fileURLWithPath: "/tmp/any/main.swift"))

        #expect(lookup == .undetermined)
    }

    /// worktree porcelain 出力 1 件のパース期待値。
    private struct WorktreeExpectation {
        var path: String
        var isMain: Bool
        var branch: String?
        var displayName: String
    }

    private struct ParseWorktreeListCase: Sendable, CustomTestStringConvertible {
        var testDescription: String
        var text: String
        var expected: [WorktreeExpectation]
    }

    private static let parseWorktreeListCases: [ParseWorktreeListCase] = [
        ParseWorktreeListCase(
            testDescription: "本体のみ",
            text: "worktree /repo/main\nHEAD abc123\nbranch refs/heads/main\n",
            expected: [
                WorktreeExpectation(path: "/repo/main", isMain: true, branch: "main", displayName: "main (main)"),
            ]
        ),
        ParseWorktreeListCase(
            testDescription: "本体 + worktree(ブランチあり)",
            text: """
            worktree /repo/main
            HEAD abc123
            branch refs/heads/main

            worktree /repo/wt
            HEAD def456
            branch refs/heads/feature-x
            """,
            expected: [
                WorktreeExpectation(path: "/repo/main", isMain: true, branch: "main", displayName: "main (main)"),
                WorktreeExpectation(
                    path: "/repo/wt", isMain: false, branch: "feature-x", displayName: "feature-x (wt)"
                ),
            ]
        ),
        ParseWorktreeListCase(
            testDescription: "detached はブランチ無しでディレクトリ名だけの表示になる",
            text: """
            worktree /repo/main
            HEAD abc123
            branch refs/heads/main

            worktree /repo/detached
            HEAD def456
            detached
            """,
            expected: [
                WorktreeExpectation(path: "/repo/main", isMain: true, branch: "main", displayName: "main (main)"),
                WorktreeExpectation(
                    path: "/repo/detached", isMain: false, branch: nil, displayName: "detached"
                ),
            ]
        ),
        ParseWorktreeListCase(
            testDescription: "bare リポジトリはブランチ無しでディレクトリ名だけの表示になる",
            text: "worktree /repo/bare\nbare\n",
            expected: [
                WorktreeExpectation(path: "/repo/bare", isMain: true, branch: nil, displayName: "bare"),
            ]
        ),
        ParseWorktreeListCase(
            testDescription: "3 件以上でも並び順(先頭=本体)を保つ",
            text: """
            worktree /repo/main
            HEAD abc123
            branch refs/heads/main

            worktree /repo/a
            HEAD def456
            branch refs/heads/feature-a

            worktree /repo/b
            HEAD ghi789
            detached
            """,
            expected: [
                WorktreeExpectation(path: "/repo/main", isMain: true, branch: "main", displayName: "main (main)"),
                WorktreeExpectation(
                    path: "/repo/a", isMain: false, branch: "feature-a", displayName: "feature-a (a)"
                ),
                WorktreeExpectation(path: "/repo/b", isMain: false, branch: nil, displayName: "b"),
            ]
        ),
        ParseWorktreeListCase(
            testDescription: "worktree 行が無ければ空",
            text: "HEAD abc123\nbranch refs/heads/main\n",
            expected: []
        ),
        ParseWorktreeListCase(
            testDescription: "空パスの worktree 行は無視される",
            text: "worktree \nHEAD abc123\nbranch refs/heads/main\n",
            expected: []
        ),
        ParseWorktreeListCase(
            testDescription: "branch 行の値が空ならブランチ無し扱い",
            text: "worktree /repo/main\nbranch \n",
            expected: [
                WorktreeExpectation(path: "/repo/main", isMain: true, branch: nil, displayName: "main"),
            ]
        ),
    ]

    @Test("worktree porcelain 出力をパースする", arguments: parseWorktreeListCases)
    private func parsesWorktreeListPorcelain(_ testCase: ParseWorktreeListCase) {
        let result = GitRepository.parseWorktreeList(testCase.text)

        #expect(result.map(\.root) == testCase.expected.map {
            URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL
        })
        #expect(result.map(\.isMain) == testCase.expected.map(\.isMain))
        #expect(result.map(\.branch) == testCase.expected.map(\.branch))
        #expect(result.map(\.displayName) == testCase.expected.map(\.displayName))
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
