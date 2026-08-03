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
    func directoryResolvesToFirstSupportedFile() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.txt", contents: "plain")
        _ = try tmp.file(named: "b.md", contents: "# hi")

        let result = await CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )

        #expect(result.exitCode == 0)
        #expect(result.message.contains("md"))
    }

    @Test("フォルダー内のファイル解決はDirectoryListerの実装を再利用する")
    func directoryResolutionUsesNaturalSortLikeDirectoryLister() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "file10.md", contents: "# ten")
        _ = try tmp.file(named: "file2.md", contents: "# two")

        let result = await CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )
        let expected = DirectoryLister.firstSupportedFile(in: tmp.url)

        #expect(result.exitCode == 0)
        #expect(expected?.lastPathComponent == "file2.md")
        #expect(result.message.contains("file2.md"))
    }

    @Test("空のフォルダーはエラーになる")
    func emptyDirectoryFails() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let result = await CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("No file found in folder"))
    }

    @Test("壊れたシンボリックリンクだけのフォルダーは空扱いせず、開けないエントリとして報告する")
    func directoryWithOnlyDanglingSymlinkReportsUnopenableEntry() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createSymbolicLink(
            at: tmp.url.appendingPathComponent("broken.mmd"),
            withDestinationURL: tmp.url.appendingPathComponent("missing.mmd")
        )

        let result = await CLICheckCommand.run(
            tmp.url.path, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("broken.mmd"))
        #expect(result.message.contains("target could not be found"))
        #expect(!result.message.contains("No file found in folder"))
    }

    /// テキストのはずのファイルに NUL が混入する事故(生成時のエスケープ漏れ等)は、
    /// 汎用の「非対応形式」ではなく NUL を名指しした理由で報告されること(TASK-260)。
    /// 判定ダブルではなく実ファイルの実バイトから DefaultFileReader.isBinary を
    /// 通すことで、拡張子・エンコーディングが正常でも NUL だけで拒否される経路を固定する。
    @Test("NUL が混入したソースファイルは NUL を理由に開けないと報告される")
    func sourceFileWithStrayNulReportsBinaryContentReason() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let source = "export const key = `${ip}\u{0}${ua}`\n"
        let file = try tmp.file(named: "visitor.ts", contents: source)

        let result = await CLICheckCommand.run(file.path, resolveFileToOpen: resolve)

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.binaryContent.cliMessage))
        #expect(!result.message.contains(RejectReason.unsupportedFormat.cliMessage))
    }

    /// NUL を含まない同等のソースは従来どおり開ける(上のテストが
    /// 「.ts だから拒否された」ではなく「NUL だから拒否された」ことの対照)。
    @Test("NUL を含まない同じ拡張子のソースは開ける")
    func sourceFileWithoutNulIsOpenable() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let source = "export const key = `${ip}\\0${ua}`\n"
        let file = try tmp.file(named: "visitor.ts", contents: source)

        let result = await CLICheckCommand.run(file.path, resolveFileToOpen: resolve)

        #expect(result.exitCode == 0)
        #expect(result.message.contains("Can open"))
    }
}
