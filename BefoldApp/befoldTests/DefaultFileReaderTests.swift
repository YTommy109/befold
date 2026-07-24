@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
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

    @Test("PNG シグネチャを持つファイルはバイナリと判定される")
    func isBinaryTrueForPNGSignature() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // PNG シグネチャ + IHDR チャンク断片(NUL が不規則に散在する)
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x80,
            0x08, 0x06, 0x00, 0x00, 0x00,
        ]
        let file = try tmp.file(named: "image.png", data: Data(bytes))

        #expect(DefaultFileReader().isBinary(at: file))
    }

    @Test("先頭 8KB が ASCII で 8KB 以降に NUL を含む UTF-8 は UTF-8 として読める")
    func utf8WithNulBeyondSniffWindowReadsAsUTF8() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // 判定窓(先頭 8KB)は純 ASCII、8KB 以降に NUL を含む UTF-8 ファイル。
        // isBinary の判定窓と decodeUnicodeText の判定窓が揃っていないと、
        // 後方の NUL を根拠に UTF-16 誤復号されて文字化けする。
        let text = String(repeating: "A", count: 9000) + "\u{0}" + "END"
        let file = try tmp.file(named: "late-nul.log", contents: text)

        let reader = DefaultFileReader()
        #expect(!reader.isBinary(at: file))
        #expect(try reader.readString(from: file) == text)
    }

    @Test("UTF-8(日本語)テキストはバイナリと判定されず正しく読める")
    func utf8JapaneseIsTextAndReadsBack() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "こんにちは, 世界\nA,B,C"
        let file = try tmp.file(named: "ja.md", contents: text)

        let reader = DefaultFileReader()
        #expect(!reader.isBinary(at: file))
        #expect(try reader.readString(from: file) == text)
    }

    /// バイトオーダー(リトル/ビッグエンディアン)を表す。テストの引数用の識別子であり、
    /// プロダクトコードの判定ロジックとは無関係。
    private enum ByteOrder: Sendable {
        case little
        case big
    }

    /// UTF-16 LE/BE(BOM 有無を問わず)テキストはバイナリと判定されず正しく読めること
    @Test(arguments: [
        (text: "name\tage\nAlice\t30", order: ByteOrder.little, includeBOM: true, filename: "excel.tsv"),
        (text: "hello world\nsecond line", order: ByteOrder.big, includeBOM: true, filename: "u16be.txt"),
        (text: "a,b,c\n1,2,3\n4,5,6", order: ByteOrder.little, includeBOM: false, filename: "nobom.csv"),
        (text: "col1,col2\nfoo,bar", order: ByteOrder.big, includeBOM: false, filename: "nobom_be.csv"),
    ])
    private func utf16IsTextAndReadsBackRegardlessOfBOM(
        text: String, order: ByteOrder, includeBOM: Bool, filename: String
    ) throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let encoding: String.Encoding = order == .little ? .utf16LittleEndian : .utf16BigEndian
        var data = try #require(text.data(using: encoding))
        if includeBOM {
            let bom: [UInt8] = order == .little ? [0xFF, 0xFE] : [0xFE, 0xFF]
            data = Data(bom) + data
        }
        let file = try tmp.file(named: filename, data: data)

        let reader = DefaultFileReader()
        #expect(!reader.isBinary(at: file))
        #expect(try reader.readString(from: file) == text)
    }

    @Test("Shift_JIS ファイルが正しくデコードされる")
    func shiftJISFileDecodesCorrectly() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "北海道特定疾患"
        let data = try #require(text.data(using: .shiftJIS))
        let file = try tmp.file(named: "data.csv", data: data)

        let reader = DefaultFileReader()
        #expect(!reader.isBinary(at: file))
        #expect(try reader.readString(from: file) == text)
    }

    @Test("EUC-JP ファイルが正しくデコードされる")
    func eucJPFileDecodesCorrectly() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "日本語テスト"
        let data = try #require(text.data(using: .japaneseEUC))
        let file = try tmp.file(named: "data.txt", data: data)

        let reader = DefaultFileReader()
        #expect(try reader.readString(from: file) == text)
    }
}
