import Foundation
@testable import mmdview
import Testing

@Suite
struct DefaultFileReaderTests {
    @Test("NULバイトを含むファイルはバイナリと判定される")
    func isBinaryTrueForNulByte() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "photo.png", contents: "PNG\0\0\0data")

        #expect(DefaultFileReader().isBinary(at: file))
    }

    @Test("NULバイトを含まないテキストファイルはバイナリと判定されない")
    func isBinaryFalseForPlainText() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "notes.txt", contents: "hello world")

        #expect(!DefaultFileReader().isBinary(at: file))
    }

    @Test("存在しないファイルはテキスト扱い(false)になる")
    func isBinaryFalseForMissingFile() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(!DefaultFileReader().isBinary(at: missing))
    }
}
