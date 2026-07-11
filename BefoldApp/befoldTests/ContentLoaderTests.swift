@testable import befold
import Foundation
import Testing

@Suite
struct ContentLoaderTests {
    private let loader = ContentLoader(fileReader: DefaultFileReader())

    @Test("テキストファイルを正常に読み込む")
    func loadTextFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "test-\(UUID()).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .code(language: "plaintext"))
        #expect(!result.isUnsupported)
        #expect(result.content == "hello")
    }

    @Test("サイズ超過ファイルは isUnsupported")
    func oversizedFileIsUnsupported() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "big-\(UUID()).txt")
        let bigData = Data(repeating: 0x41, count: ContentLoader.maxFileSizeBytes + 1)
        try bigData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .code(language: "plaintext"))
        #expect(result.isUnsupported)
        #expect(result.content == "")
    }

    @Test("バイナリファイルは isUnsupported")
    func binaryFileIsUnsupported() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "bin-\(UUID()).dat")
        var data = Data(repeating: 0x00, count: 100)
        data[0] = 0xFF
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .code(language: "plaintext"))
        #expect(result.isUnsupported)
    }

    @Test("画像ファイルは base64 エンコードされる")
    func imageFileIsBase64Encoded() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "img-\(UUID()).png")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .image(mimeType: "image/png"))
        #expect(!result.isUnsupported)
        #expect(result.content == data.base64EncodedString())
    }
}
