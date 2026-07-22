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
        #expect(String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == expectedVersion)
    }

    /// テストバイナリと同じビルドディレクトリ内にある `befold` 実行ファイルのパスを解決する。
    /// SPM(.build レイアウト)と xcodebuild(befold.app/Contents/MacOS/befold)の両方に対応する。
    private static func builtExecutableURL() throws -> URL {
        let testBinaryDirectory = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
        let spmCandidate = testBinaryDirectory.appendingPathComponent("befold")
        if FileManager.default.isExecutableFile(atPath: spmCandidate.path) {
            return spmCandidate
        }
        let xcodeCandidate = testBinaryDirectory
            .appendingPathComponent("befold.app/Contents/MacOS/befold")
        try #require(
            FileManager.default.isExecutableFile(atPath: xcodeCandidate.path),
            "befold executable not found in SPM or xcodebuild layout"
        )
        return xcodeCandidate
    }
}

/// `Bundle(for:)` 用のマーカークラス(テストターゲットのバンドルを特定するため)。
private final class BundleToken {}
