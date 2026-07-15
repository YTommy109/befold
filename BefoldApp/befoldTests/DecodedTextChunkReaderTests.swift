import BefoldKit
import Testing

@Suite
struct DecodedTextChunkReaderTests {
    @Test("空文字列は即座に終了する")
    func emptyText() async {
        let reader = DecodedTextChunkReader(text: "")
        let result = await reader.readNextChunk()
        #expect(result.text == "")
        #expect(result.isAtEnd == true)
    }

    @Test("1000 行未満のテキストは 1 チャンクで返る")
    func singleChunk() async {
        let text = (1 ... 10).map { "line\($0)" }.joined(separator: "\n") + "\n"
        let reader = DecodedTextChunkReader(text: text)
        let result = await reader.readNextChunk()
        #expect(result.text == text)
        #expect(result.isAtEnd == true)
    }

    @Test("1000 行を超えるテキストは複数チャンクに分割される")
    func multipleChunks() async {
        let lines = (1 ... 2500).map { "line\($0)\n" }
        let text = lines.joined()
        let reader = DecodedTextChunkReader(text: text)

        let first = await reader.readNextChunk()
        #expect(first.isAtEnd == false)
        #expect(first.text.count(where: { $0 == "\n" }) == 1000)

        let second = await reader.readNextChunk()
        #expect(second.isAtEnd == false)
        #expect(second.text.count(where: { $0 == "\n" }) == 1000)

        let third = await reader.readNextChunk()
        #expect(third.isAtEnd == true)
        #expect(third.text.count(where: { $0 == "\n" }) == 500)

        let reconstructed = first.text + second.text + third.text
        #expect(reconstructed == text)
    }

    @Test("CSV 引用フィールド内の改行はチャンク境界にならない")
    func csvQuotedNewlines() async {
        var lines: [String] = []
        for row in 1 ... 999 {
            lines.append("field\(row)\n")
        }
        lines.append("\"quoted\nfield\"\n")
        lines.append("after\n")
        let text = lines.joined()

        let reader = DecodedTextChunkReader(text: text, respectsCSVQuotes: true)
        let first = await reader.readNextChunk()
        // 引用内の改行はカウントされないため、1000 行目の引用フィールドは
        // 最初のチャンクに含まれる
        #expect(first.text.contains("quoted\nfield"))
        #expect(first.isAtEnd == false)

        let second = await reader.readNextChunk()
        #expect(second.text == "after\n")
        #expect(second.isAtEnd == true)
    }

    @Test("末尾に改行がないテキストも正しく処理する")
    func noTrailingNewline() async {
        let text = "first\nsecond"
        let reader = DecodedTextChunkReader(text: text)
        let result = await reader.readNextChunk()
        #expect(result.text == text)
        #expect(result.isAtEnd == true)
    }

    @Test("読み終えた後の追加呼び出しは空を返す")
    func readAfterEnd() async {
        let reader = DecodedTextChunkReader(text: "hello\n")
        _ = await reader.readNextChunk()
        let extra = await reader.readNextChunk()
        #expect(extra.text == "")
        #expect(extra.isAtEnd == true)
    }
}
