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
        #expect(result.message.contains("\(("graph TD;" as String).utf8.count)バイト"))
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

    @Test("空のフォルダーはエラーになる")
    func emptyDirectoryFails() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let result = CLICheckCommand.run([tmp.url.path])

        #expect(result.exitCode != 0)
    }
}
