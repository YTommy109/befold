import BefoldKit
import Testing

/// バナーの表示行数の数え方(GUI 本体と 1 回描画ホストが共有する単一情報源)を検証する。
@Suite
struct DisplayedLineCountTests {
    @Test("空文字列の表示行数は 0")
    func emptyContentIsZero() {
        #expect(DisplayedLineCount.count(of: "") == 0)
    }

    @Test("末尾改行なしの単一行は 1 行として数える")
    func singleLineWithoutTrailingNewline() {
        #expect(DisplayedLineCount.count(of: "single line") == 1)
    }

    @Test("末尾が改行なら途中行を足さない")
    func trailingNewlineDoesNotAddPartialLine() {
        #expect(DisplayedLineCount.count(of: "a\nb\n") == 2)
        #expect(DisplayedLineCount.count(of: "a\nb") == 2)
    }

    @Test("既知の改行数からの算出は全走査版と一致する")
    func incrementalCountMatchesFullScan() {
        for content in ["", "a", "a\n", "a\nb", "a\nb\n"] {
            let newlines = content.utf8.count { $0 == 0x0A }
            #expect(DisplayedLineCount.count(newlines: newlines, in: content) == DisplayedLineCount.count(of: content))
        }
    }
}
