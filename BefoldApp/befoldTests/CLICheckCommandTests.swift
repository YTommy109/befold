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

    /// fileSize が nil を返すファイル(権限不足・非通常ファイル等)でも、GUI は実データを読んで
    /// fileTooLarge で拒否する。--check がサイズ 0 とみなして openable と報告してはならない。
    @Test("サイズを取得できない超過ファイルを openable と報告しない")
    func fileSizeUnknownOversizedFileIsRejected() async {
        let url = URL(fileURLWithPath: "/tmp/huge.html")
        let oversized = String(repeating: "a", count: ContentLoader.maxTextFileSizeBytes + 1)
        let reader = InMemoryFileReader(files: [url.path: oversized])
        reader.setSizeUnknown(true, at: url)

        let result = await CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.fileTooLarge.cliMessage))
    }

    /// 非行指向タイプの GUI 側判定はデコード後の UTF-8 バイト数で行われる(ViewerLoadPipeline.loadFull)。
    /// Shift_JIS の日本語は 2 バイト/文字が UTF-8 で 3 バイト/文字へ膨らむため、
    /// raw バイト数だけを見る判定では上限内に見えても GUI は拒否する。
    @Test("raw サイズは上限内でもデコード後に超過する Shift_JIS ファイルを拒否する")
    func shiftJISFileExceedingLimitAfterDecodeIsRejected() async throws {
        let url = URL(fileURLWithPath: "/tmp/sjis.html")
        // 4.5M 文字: Shift_JIS で 9MB(上限内)、UTF-8 デコード後は 13.5MB(上限超過)。
        let japanese = String(repeating: "あ", count: 4_500_000)
        let sjis = try #require(japanese.data(using: .shiftJIS))
        #expect(sjis.count < ContentLoader.maxTextFileSizeBytes)
        #expect(japanese.utf8.count > ContentLoader.maxTextFileSizeBytes)
        let reader = InMemoryFileReader()
        reader.setDataFile(sjis, at: url)

        let result = await CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.fileTooLarge.cliMessage))
    }

    @Test("開けるファイルはサイズと型を含めて成功する")
    func openableFileSucceedsWithSizeAndType() async {
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let reader = InMemoryFileReader(files: [url.path: "graph TD;"])

        let result = await CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode == 0)
        #expect(result.message.contains("mmd"))
        #expect(result.message.contains("\(("graph TD;" as String).utf8.count) bytes"))
    }

    @Test("存在しないパスはエラーになる")
    func missingPathFails() async {
        let reader = InMemoryFileReader()

        let result = await CLICheckCommand.run(
            "/tmp/missing.mmd", fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/missing.mmd"))
    }

    @Test("サイズ上限を超えるテキストファイルは理由付きで開けないと判定される")
    func oversizedTextFileIsRejected() async {
        let url = URL(fileURLWithPath: "/tmp/big.html")
        let reader = InMemoryFileReader(files: [url.path: "<h1>big</h1>"])
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: url)

        let result = await CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.fileTooLarge.cliMessage))
    }

    @Test("拡張子は既知だが内容がバイナリのファイルはバイナリを理由に開けないと判定される")
    func binaryContentForTextExtensionIsRejected() async {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let reader = InMemoryFileReader(files: [url.path: "not really markdown"])
        reader.setBinary(true, at: url)

        let result = await CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.binaryContent.cliMessage))
    }

    @Test("サイズ超過かつ内容がバイナリの場合、実際のオープン経路と同じくバイナリ判定を優先する")
    func oversizedAndBinaryContentPrefersUnsupportedFormatOverFileTooLarge() async {
        let url = URL(fileURLWithPath: "/tmp/big-binary.md")
        let reader = InMemoryFileReader(files: [url.path: "not really markdown"])
        reader.setBinary(true, at: url)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: url)

        let result = await CLICheckCommand.run(
            url.path, fileReader: reader, resolveFileToOpen: resolve
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains(RejectReason.binaryContent.cliMessage))
        #expect(!result.message.contains(RejectReason.fileTooLarge.cliMessage))
    }
}
