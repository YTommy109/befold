@testable import befold
import BefoldTestSupport
import Foundation
import Testing

struct GitRepositoryTests {
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
        let repo = GitRepository()
        let lookup = repo.root(forFileAt: temp.url.appendingPathComponent("main.swift"))
        let root = try #require(lookup.foundRoot)
        #expect(root.standardizedFileURL == temp.url.standardizedFileURL)
        #expect(repo.trackedFiles(at: root)?.map(\.lastPathComponent) == ["main.swift"])
    }

    /// git が動いて「リポジトリではない」と答えた場合と、git を実行できず不明な場合とを
    /// 区別する(キャッシュ層は前者だけを覚えるため、取り違えると失敗が固定化する)。
    @Test("git 管理外は notARepository として返る")
    func reportsNotARepositoryOutsideRepo() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        #expect(GitRepository().root(forFileAt: temp.url.appendingPathComponent("x.md")) == .notARepository)
    }

    @Test("index の更新で fingerprint が変わる")
    func fingerprintChangesOnIndexUpdate() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = GitRepository()
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
        let fingerprint = GitRepository().indexFingerprint(at: work.url)
        let attributes = try FileManager.default.attributesOfItem(atPath: indexURL.path)
        let expected = attributes[.modificationDate] as? Date
        #expect(fingerprint != nil)
        #expect(fingerprint == expected)
    }
}
