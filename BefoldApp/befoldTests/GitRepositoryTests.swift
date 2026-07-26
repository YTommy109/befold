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
