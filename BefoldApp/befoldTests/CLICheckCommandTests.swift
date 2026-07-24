@testable import befold
@testable import BefoldCLI
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct CLICheckCommandTests {
    private let resolve: (URL, any FileReading) -> URL? = {
        DirectoryLister.resolveFileToOpen(at: $0, fileReader: $1)
    }

    @Test("開けるファイルはサイズと型を含めて成功する")
    func openableFileSucceedsWithSizeAndType() {
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let reader = InMemoryFileReader(files: [url.path: "graph TD;"])

        let result = CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode == 0)
        #expect(result.message.contains("mmd"))
        #expect(result.message.contains("\(("graph TD;" as String).utf8.count) bytes"))
    }

    @Test("存在しないパスはエラーになる")
    func missingPathFails() {
        let reader = InMemoryFileReader()

        let result = CLICheckCommand.run(
            "/tmp/missing.mmd", fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/missing.mmd"))
    }

    @Test("サイズ上限を超えるテキストファイルは理由付きで開けないと判定される")
    func oversizedTextFileIsRejected() {
        let url = URL(fileURLWithPath: "/tmp/big.md")
        let reader = InMemoryFileReader(files: [url.path: "# big"])
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: url)

        let result = CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.fileTooLarge.cliMessage))
    }

    @Test("拡張子は既知だが内容がバイナリのファイルは未対応形式として開けないと判定される")
    func binaryContentForTextExtensionIsRejected() {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let reader = InMemoryFileReader(files: [url.path: "not really markdown"])
        reader.setBinary(true, at: url)

        let result = CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.unsupportedFormat.cliMessage))
    }

    @Test("サイズ超過かつ内容がバイナリの場合、実際のオープン経路と同じくバイナリ判定を優先する")
    func oversizedAndBinaryContentPrefersUnsupportedFormatOverFileTooLarge() {
        let url = URL(fileURLWithPath: "/tmp/big-binary.md")
        let reader = InMemoryFileReader(files: [url.path: "not really markdown"])
        reader.setBinary(true, at: url)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: url)

        let result = CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.unsupportedFormat.cliMessage))
        #expect(!result.message.contains(RejectReason.fileTooLarge.cliMessage))
    }
}
