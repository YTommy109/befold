import BefoldKit
import Foundation
import Testing

@Suite
struct ContentLoaderTests {
    private let loader = ContentLoader(fileReader: DefaultFileReader())

    @Test("テキストファイルを正常に読み込む")
    func loadTextFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.txt", contents: "hello")

        let result = loader.load(from: file, fileType: .code(language: "plaintext"))
        #expect(result.rejectReason == nil)
        #expect(result.content == "hello")
        #expect(!result.isTruncated)
    }

    @Test("サイズ超過ファイルは fileTooLarge")
    func oversizedFileIsRejected() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/big.txt")
        reader.setFile("hello", at: file)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.load(from: file, fileType: .code(language: "plaintext"))
        #expect(result.rejectReason == .fileTooLarge)
        #expect(result.content == "")
    }

    @Test("バイナリファイルは unsupportedFormat")
    func binaryFileIsRejected() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        var data = Data(repeating: 0x00, count: 100)
        data[0] = 0xFF
        let file = try tmp.file(named: "bin.dat", data: data)

        let result = loader.load(from: file, fileType: .code(language: "plaintext"))
        #expect(result.rejectReason == .unsupportedFormat)
    }

    @Test("画像ファイルは base64 エンコードされる")
    func imageFileIsBase64Encoded() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let file = try tmp.file(named: "img.png", data: data)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"))
        #expect(result.rejectReason == nil)
        #expect(result.content == data.base64EncodedString())
    }

    @Test("loadPreview は先頭のみ返し isTruncated を設定する")
    func loadPreviewReturnsTruncated() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let lines = (0 ..< 600_000).map { "line\($0),data\($0)" }.joined(separator: "\n")
        let file = try tmp.file(named: "big.csv", contents: lines)

        let result = loader.loadPreview(from: file, fileType: .csv(delimiter: ","))
        #expect(result.rejectReason == nil)
        #expect(result.isTruncated)
        #expect(result.content.utf8.count <= ContentLoader.previewSizeBytes)
        #expect(result.content.hasSuffix("\n"))
    }

    @Test("loadPreview で閾値以下テキストは isTruncated = false")
    func loadPreviewSmallTextIsNotTruncated() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "small.csv", contents: "a,b\n1,2")

        let result = loader.loadPreview(from: file, fileType: .csv(delimiter: ","))
        #expect(result.rejectReason == nil)
        #expect(!result.isTruncated)
        #expect(result.content == "a,b\n1,2")
    }

    @Test("loadPreview でサイズ不明テキストは truncated パスで読み込む")
    func loadPreviewUnknownSizeIsTruncated() {
        let file = URL(fileURLWithPath: "/files/unknown.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2", at: file)
        reader.setSizeUnknown(true, at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.loadPreview(from: file, fileType: .csv(delimiter: ","))
        #expect(result.rejectReason == nil)
        #expect(result.isTruncated)
    }

    @Test("loadPreview で上限以下のバイナリは通常読み込み")
    func loadPreviewBinaryFallsThrough() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let file = try tmp.file(named: "img.png", data: data)

        let result = loader.loadPreview(from: file, fileType: .image(mimeType: "image/png"))
        #expect(result.rejectReason == nil)
        #expect(result.content == data.base64EncodedString())
    }
}
