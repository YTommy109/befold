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
    }

    @Test("サイズ超過ファイルは fileTooLarge")
    func oversizedFileIsRejected() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/big.txt")
        reader.setFile("hello", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)
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
}
