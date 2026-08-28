import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct ContentLoaderTests {
    @Test("サイズ超過ファイルは fileTooLarge")
    func oversizedFileIsRejected() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/big.png")
        reader.setFile("hello", at: file)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"), computeHash: true)
        #expect(result.rejectReason == .fileTooLarge)
        #expect(result.content == "")
        // 拒否された読み込みに hash を与えないことで、拒否理由だけが変わる遷移が
        // 同一内容スキップに握り潰されるのを防ぐ(LoadedContent.contentHash の doc 参照)。
        #expect(result.contentHash == nil)
    }

    @Test("読み込みに失敗したファイルは unsupportedFormat")
    func readFailureIsRejected() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/bin.png")
        reader.setFile("data", at: file)
        reader.setReadError(true, at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"), computeHash: true)
        #expect(result.rejectReason == .unsupportedFormat)
        #expect(result.contentHash == nil)
    }

    @Test("画像ファイルは base64 エンコードされる")
    func imageFileIsBase64Encoded() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/img.png")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        reader.setDataFile(data, at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"), computeHash: true)
        #expect(result.rejectReason == nil)
        #expect(result.content == data.base64EncodedString())
    }

    @Test("computeHash: true では同一内容に同じ hash、内容が変われば違う hash が付く")
    func contentHashTracksData() {
        let reader = InMemoryFileReader()
        let same = URL(fileURLWithPath: "/files/same.png")
        let other = URL(fileURLWithPath: "/files/other.png")
        reader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47]), at: same)
        reader.setDataFile(Data([0x89, 0x50, 0x4E, 0x48]), at: other)
        let loader = ContentLoader(fileReader: reader)
        let type = FileType.image(mimeType: "image/png")

        let first = loader.load(from: same, fileType: type, computeHash: true)
        let again = loader.load(from: same, fileType: type, computeHash: true)
        let different = loader.load(from: other, fileType: type, computeHash: true)

        #expect(first.contentHash != nil)
        #expect(first.contentHash == again.contentHash)
        #expect(first.contentHash != different.contentHash)
    }

    @Test("computeHash: false では hash を計算しない(1 回描画ホスト向け)")
    func computeHashFalseSkipsHash() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/img.png")
        reader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47]), at: file)
        let loader = ContentLoader(fileReader: reader)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"), computeHash: false)
        #expect(result.rejectReason == nil)
        #expect(result.contentHash == nil)
    }
}
