import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// befold-cli を実サブプロセスとして起動して検証するシナリオテスト。
///
/// in-process で検証できることはここでは扱わない。実バイナリでしか確かめられない
/// 「起動して名乗るバージョン」と「カレントディレクトリ基準のパス解決」に絞る。
@Suite(.timeLimit(.minutes(1)))
struct BefoldCLIIntegrationTests {
    @Test("befold-cli --version は標準出力にバージョン文字列を印字し終了コード 0 で終了する")
    func versionFlagPrintsVersionAndExitsSuccessfully() throws {
        let result = try runCLI(["--version"])

        #expect(result.status == 0)
        #expect(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                == AppVersion.current
        )
    }

    @Test("befold-cli --check <相対パス> はカレントディレクトリ基準で解決される")
    func checkFlagResolvesRelativePath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "rel.mmd", contents: "graph TD;")

        let result = try runCLI(
            ["--check", "rel.mmd"],
            currentDirectory: file.deletingLastPathComponent()
        )

        #expect(result.status == 0)
        #expect(result.stdout.contains("Can open:"))
    }

    /// befold-cli を起動し、終了コードと出力を返す。
    ///
    /// 出力は `Pipe` ではなく一時ファイルへリダイレクトする。パイプはバッファ(64KB)が
    /// 埋まると子プロセスの `write` がブロックし、親が読み出すまで互いに待ち合う。
    /// ファイルにはその上限が無いため、読み出しの順序やタイミングを気にせず扱える。
    ///
    /// この関数は同期のため `.timeLimit` では `waitUntilExit` を中断できない。
    /// 代わりに `timeout` までポーリングし、応答しなければ終了させて失敗を記録する。
    private func runCLI(
        _ arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval = 30
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let tmp = try TempDir(prefix: "befold-cli-run")
        defer { withExtendedLifetime(tmp) {} }
        let outURL = try tmp.file(named: "stdout.txt", contents: "")
        let errURL = try tmp.file(named: "stderr.txt", contents: "")
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer {
            try? outHandle.close()
            try? errHandle.close()
        }

        let process = Process()
        process.executableURL = try Self.builtExecutableURL()
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = outHandle
        process.standardError = errHandle
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            Issue.record("befold-cli \(arguments) が \(timeout) 秒以内に終了しなかった")
            process.terminate()
            let killDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < killDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()

        return (
            status: process.terminationStatus,
            stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
            stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        )
    }

    /// テストバイナリと同じビルドディレクトリ内の `befold-cli` を解決する。
    /// SPM(.build レイアウト)と xcodebuild(befold.app/Contents/MacOS/befold-cli)の
    /// 両方に対応する。
    private static func builtExecutableURL() throws -> URL {
        let testBinaryDirectory = Bundle(
            for: BundleToken.self
        ).bundleURL.deletingLastPathComponent()
        let spmCandidate = testBinaryDirectory
            .appendingPathComponent("befold-cli")
        if FileManager.default
            .isExecutableFile(atPath: spmCandidate.path)
        {
            return spmCandidate
        }
        let xcodeCandidate = testBinaryDirectory
            .appendingPathComponent(
                "befold.app/Contents/MacOS/befold-cli"
            )
        try #require(
            FileManager.default
                .isExecutableFile(atPath: xcodeCandidate.path),
            "befold-cli executable not found in SPM or xcodebuild layout"
        )
        return xcodeCandidate
    }
}

private final class BundleToken {}
