import ArgumentParser
@testable import befold
@testable import BefoldCLI
import Foundation
import Testing

/// befold-cli バイナリを実サブプロセスとして起動して検証するシナリオテスト。
@Suite
struct BefoldCLIIntegrationTests {
    @Test("befold-cli --version は標準出力にバージョン文字列を印字し終了コード 0 で終了する")
    func versionFlagPrintsVersionAndExitsSuccessfully() throws {
        let executableURL = try Self.builtExecutableURL()
        let expectedVersion = AppVersion.current

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(
            String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == expectedVersion
        )
    }

    @Test("befold-cli --help に --check/--bookmark と全表示オプションが表示される")
    func helpDisplaysAllOptionsAtTopLevel() throws {
        let executableURL = try Self.builtExecutableURL()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--help"]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: output, encoding: .utf8) ?? ""

        #expect(process.terminationStatus == 0)
        #expect(text.contains("--check"))
        #expect(text.contains("--bookmark"))
        #expect(text.contains("--hidden-files"))
        #expect(text.contains("--sort"))
        #expect(text.contains("--line-numbers"))
        #expect(text.contains("--source"))
        #expect(text.contains("--preview"))
    }

    @Test(
        "befold-cli --check <path> は終了コード 0 でチェック結果を出力する"
    )
    func checkFlagRunsAsRealSubprocess() throws {
        let executableURL = try Self.builtExecutableURL()
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--check", file.path]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(
            String(data: output, encoding: .utf8)?
                .contains("Can open:") == true
        )
    }

    @Test(
        "befold-cli --check <相対パス> はカレントディレクトリ基準で解決される"
    )
    func checkFlagResolvesRelativePath() throws {
        let executableURL = try Self.builtExecutableURL()
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "rel.mmd", contents: "graph TD;")

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = file.deletingLastPathComponent()
        process.arguments = ["--check", "rel.mmd"]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(
            String(data: output, encoding: .utf8)?
                .contains("Can open:") == true
        )
    }

    @Test(
        "befold-cli --check を引数なしで呼ぶと終了コード非ゼロ"
    )
    func checkFlagWithoutPathFails() throws {
        let executableURL = try Self.builtExecutableURL()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--check"]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
    }

    @Test(
        "befold-cli --check <存在しないパス> は終了コード非ゼロを返す"
    )
    func checkFlagWithMissingPathFails() throws {
        let executableURL = try Self.builtExecutableURL()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--check", "/no/such/file.mmd"]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let output = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
        #expect(
            String(data: output, encoding: .utf8)?
                .contains("No such path:") == true
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
