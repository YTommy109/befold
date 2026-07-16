import BefoldKit
import Foundation
import Testing

@Suite
struct TextEncodingTests {
    @Test("UTF-8 BOM を検出する")
    func detectsUtf8Bom() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf8)
        #expect(bom?.bomLength == 3)
    }

    @Test("UTF-16 LE BOM を検出する")
    func detectsUtf16LeBom() {
        let data = Data([0xFF, 0xFE, 0x41, 0x00])
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf16LittleEndian)
        #expect(bom?.bomLength == 2)
    }

    @Test("UTF-16 BE BOM を検出する")
    func detectsUtf16BeBom() {
        let data = Data([0xFE, 0xFF, 0x00, 0x41])
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf16BigEndian)
        #expect(bom?.bomLength == 2)
    }

    @Test("UTF-32 LE BOM を検出する")
    func detectsUtf32LeBom() {
        let data = Data([0xFF, 0xFE, 0x00, 0x00])
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf32LittleEndian)
        #expect(bom?.bomLength == 4)
    }

    @Test("BOM がなければ nil を返す")
    func noBomReturnsNil() {
        let data = Data("hello".utf8)
        #expect(TextEncoding.detectBOM(data) == nil)
    }
}
