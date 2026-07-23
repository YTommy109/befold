import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct ContentLoaderTests {
    private let loader = ContentLoader(fileReader: DefaultFileReader())

    @Test("サイズ超過ファイルは fileTooLarge")
    func oversizedFileIsRejected() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/big.png")
        reader.setFile("hello", at: file)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"))
        #expect(result.rejectReason == .fileTooLarge)
        #expect(result.content == "")
    }

    @Test("読み込みに失敗したファイルは unsupportedFormat")
    func readFailureIsRejected() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/bin.png")
        reader.setFile("data", at: file)
        reader.setReadError(true, at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"))
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
