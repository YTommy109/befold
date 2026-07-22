@testable import befold
import BefoldKit
import Foundation
import Testing

@Suite
struct CLICheckCommandTests {
    @Test("開けるファイルはサイズと型を含めて成功する")
    func openableFileSucceedsWithSizeAndType() {
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let reader = InMemoryFileReader(files: [url.path: "graph TD;"])

        let result = CLICheckCommand.run([url.path], fileReader: reader)

        #expect(result.exitCode == 0)
        #expect(result.message.contains("mmd"))
        #expect(result.message.contains("\(("graph TD;" as String).utf8.count) bytes"))
    }

    @Test("存在しないパスはエラーになる")
    func missingPathFails() {
        let reader = InMemoryFileReader()

        let result = CLICheckCommand.run(["/tmp/missing.mmd"], fileReader: reader)

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/missing.mmd"))
    }

    @Test("サイズ上限を超えるテキストファイルは理由付きで開けないと判定される")
    func oversizedTextFileIsRejected() {
        let url = URL(fileURLWithPath: "/tmp/big.md")
        let reader = InMemoryFileReader(files: [url.path: "# big"])
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: url)

        let result = CLICheckCommand.run([url.path], fileReader: reader)

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.fileTooLarge.localizedMessage))
    }

    @Test("拡張子は既知だが内容がバイナリのファイルは未対応形式として開けないと判定される")
    func binaryContentForTextExtensionIsRejected() {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let reader = InMemoryFileReader(files: [url.path: "not really markdown"])
        reader.setBinary(true, at: url)

        let result = CLICheckCommand.run([url.path], fileReader: reader)

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.unsupportedFormat.localizedMessage))
    }

    @Test("サイズ超過かつ内容がバイナリの場合、実際のオープン経路と同じくバイナリ判定を優先する(TASK-73.8)")
    func oversizedAndBinaryContentPrefersUnsupportedFormatOverFileTooLarge() {
        let url = URL(fileURLWithPath: "/tmp/big-binary.md")
        let reader = InMemoryFileReader(files: [url.path: "not really markdown"])
        reader.setBinary(true, at: url)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: url)

        let result = CLICheckCommand.run([url.path], fileReader: reader)

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.unsupportedFormat.localizedMessage))
        #expect(!result.message.contains(RejectReason.fileTooLarge.localizedMessage))
    }

    @Test("引数の数が不正な場合は usage エラーになる")
    func invalidArgumentCountReturnsUsageError() {
        #expect(CLICheckCommand.run([]).exitCode == 64)
        #expect(CLICheckCommand.run(["a", "b"]).exitCode == 64)
    }

    @Test("フォルダーを指定すると対応形式優先で最初のファイルを判定する")
    func directoryResolvesToFirstSupportedFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.txt", contents: "plain")
        _ = try tmp.file(named: "b.md", contents: "# hi")

        let result = CLICheckCommand.run([tmp.url.path])

        #expect(result.exitCode == 0)
        #expect(result.message.contains("md"))
    }

    @Test("フォルダー内のファイル解決はDirectoryListerの実装を再利用する(TASK-73.12/TASK-80)")
    func directoryResolutionUsesNaturalSortLikeDirectoryLister() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // バイト列比較では "file10.md" < "file2.md" となり誤った順序になるが、
        // 自然順ソート(localizedStandardCompare)では "file2.md" が先に来る
        // (DirectoryLister.firstSupportedFile/GUI が実際に開くファイルと一致させる)。
        _ = try tmp.file(named: "file10.md", contents: "# ten")
        _ = try tmp.file(named: "file2.md", contents: "# two")

        let result = CLICheckCommand.run([tmp.url.path])
        let expected = DirectoryLister.firstSupportedFile(in: tmp.url)

        #expect(result.exitCode == 0)
        #expect(expected?.lastPathComponent == "file2.md")
        #expect(result.message.contains("file2.md"))
    }

    @Test("空のフォルダーはエラーになる")
    func emptyDirectoryFails() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let result = CLICheckCommand.run([tmp.url.path])

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

        let result = CLICheckCommand.run([tmp.url.path])

        #expect(result.exitCode != 0)
        #expect(result.message.contains("broken.mmd"))
        #expect(result.message.contains("target could not be found"))
        // 「フォルダーが空」の文言とは区別されること(実際の原因を報告する)。
        #expect(!result.message.contains("No file found in folder"))
    }
}
