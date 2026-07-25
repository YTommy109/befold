@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// `GitCommandRunner` が全 git 呼び出しへ無害化オプションを前置することを固定する。
/// 開いた文書のリポジトリ設定(`core.fsmonitor`)による任意コマンド実行を防ぐ要のため、
/// 将来のリファクタで静かに落ちないよう引数構築と実挙動の両方で押さえる。
struct GitCommandRunnerTests {
    @Test("git 呼び出しには常に core.fsmonitor 無効化が前置される")
    func alwaysPrependsFsmonitorHardening() {
        let args = GitCommandRunner.processArguments(for: ["ls-files", "-z"])

        // サブコマンドより前に置かないと git が解釈しないため、位置まで固定する。
        #expect(args == ["git", "-c", "core.fsmonitor=", "-c", "core.hooksPath=/dev/null", "ls-files", "-z"])
    }

    @Test("引数無しの呼び出しでも無害化オプションは落ちない")
    func hardeningSurvivesEmptyArguments() {
        // hardeningOptions を参照して組み立てると恒真になるため、期待値は直値で書く。
        #expect(GitCommandRunner.processArguments(for: [])
            == ["git", "-c", "core.fsmonitor=", "-c", "core.hooksPath=/dev/null"])
    }

    @Test("core.fsmonitor を仕込んだリポジトリでもコマンドが実行されない")
    func doesNotExecuteRepositoryFsmonitorCommand() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let marker = temp.url.appendingPathComponent("marker")
        try makeRepoWithFsmonitor(temp.url, marker: marker)

        // 対照: 無害化しない生の git では実際に実行されることを確かめる。ここが再現しない
        // 環境(fsmonitor 未対応の git など)ではこのテストは検証力を持たないため、
        // 引数構築テスト(alwaysPrependsFsmonitorHardening)側の固定に委ねて抜ける。
        rawGit(temp.url, ["ls-files", "-z"])
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        try FileManager.default.removeItem(at: marker)

        _ = GitCommandRunner().run(["ls-files", "-z"], in: temp.url)

        #expect(FileManager.default.fileExists(atPath: marker.path) == false)
    }

    /// 無害化オプションを通さずに git を実行する(対照用)。
    private func rawGit(_ dir: URL, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// marker を作るだけのフックを `core.fsmonitor` に仕込んだリポジトリを作る
    /// (`.git/` 込みのアーカイブを展開して開いた状況の再現)。
    private func makeRepoWithFsmonitor(_ dir: URL, marker: URL) throws {
        rawGit(dir, ["init"])
        rawGit(dir, ["config", "user.email", "t@example.com"])
        rawGit(dir, ["config", "user.name", "t"])
        try "print(1)".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        rawGit(dir, ["add", "main.swift"])
        rawGit(dir, ["commit", "-m", "init"])

        let hook = dir.appendingPathComponent("fsmonitor-hook.sh")
        // exit 1 で git にフック未対応を伝え、監視結果の解釈まで進ませない。
        try "#!/bin/sh\ntouch \"\(marker.path)\"\nexit 1\n"
            .write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        rawGit(dir, ["config", "core.fsmonitor", hook.path])
    }
}
