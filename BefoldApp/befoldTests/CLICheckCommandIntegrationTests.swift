@testable import befold
@testable import BefoldCLI
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// フォルダー解決・dangling symlink の判定は実ディレクトリ列挙と symlink 解決そのものが
/// 検証対象のため、InMemoryFileReader では代替できず実 FS を使う Integration スイート。
@Suite
struct CLICheckCommandIntegrationTests {
    private let resolve: (URL, any FileReading) -> URL? = {
        DirectoryLister.resolveFileToOpen(at: $0, fileReader: $1)
    }

    @Test("フォルダーを指定すると対応形式優先で最初のファイルを判定する")
    func directoryResolvesToFirstSupportedFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.txt", contents: "plain")
        _ = try tmp.file(named: "b.md", contents: "# hi")

        let result = CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )

        #expect(result.exitCode == 0)
        #expect(result.message.contains("md"))
    }

    @Test("フォルダー内のファイル解決はDirectoryListerの実装を再利用する")
    func directoryResolutionUsesNaturalSortLikeDirectoryLister() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "file10.md", contents: "# ten")
        _ = try tmp.file(named: "file2.md", contents: "# two")

        let result = CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )
        let expected = DirectoryLister.firstSupportedFile(in: tmp.url)

        #expect(result.exitCode == 0)
        #expect(expected?.lastPathComponent == "file2.md")
        #expect(result.message.contains("file2.md"))
    }

    @Test("空のフォルダーはエラーになる")
    func emptyDirectoryFails() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let result = CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("No file found in folder"))
    }

    @Test("壊れたシンボリックリンクだけのフォルダーは空扱いせず、開けないエントリとして報告する")
    func directoryWithOnlyDanglingSymlinkReportsUnopenableEntry() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createSymbolicLink(
            at: tmp.url.appendingPathComponent("broken.mmd"),
            withDestinationURL: tmp.url.appendingPathComponent("missing.mmd")
        )

        let result = CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("broken.mmd"))
        #expect(result.message.contains("target could not be found"))
        #expect(!result.message.contains("No file found in folder"))
    }
}
