import ArgumentParser
@testable import befold
import Foundation
import Testing

/// BefoldRootCommand(swift-argument-parser への移行、TASK-76)のうち、ビルド済み実行ファイルを
/// 実サブプロセス起動して検証するシナリオテスト。
@Suite
struct BefoldRootCommandIntegrationTests {
    @Test("befold --version を実行すると標準出力にバージョン文字列を印字し、終了コード0で終了する")
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
        #expect(String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == expectedVersion)
    }

    @Test("open 専用オプションはトップレベル --help に表示されない(befold open --help に委ねる)")
    func openOptionsDoNotAppearInTopLevelHelp() throws {
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

        #expect(!text.contains("--hidden-files"))
        #expect(!text.contains("--sort"))
        #expect(!text.contains("--line-numbers"))
        #expect(text.contains("befold open --help"))
    }

    /// テストバイナリと同じ `.build` ディレクトリ内にある `befold` 実行ファイルのパスを解決する。
    private static func builtExecutableURL() throws -> URL {
        let testBinaryDirectory = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
        let executableURL = testBinaryDirectory.appendingPathComponent("befold")
        #expect(FileManager.default.isExecutableFile(atPath: executableURL.path))
        return executableURL
    }
}

/// `Bundle(for:)` 用のマーカークラス(テストターゲットのバンドルを特定するため)。
private final class BundleToken {}
