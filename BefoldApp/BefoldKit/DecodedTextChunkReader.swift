import Foundation

/// 全量デコード済みの文字列を行単位のチャンクで逐次提供する actor。
/// Shift_JIS 等のレガシーエンコーディングで LineChunkReader が使えない場合に、
/// 全量デコード後のチャンク送信を実現する。
///
/// 改行判定は Unicode スカラーレベルで行う。Swift の Character は `\r\n` を
/// 単一グラフェムクラスタとして扱い `== "\n"` がマッチしないため、
/// スカラーの `0x0A` (LF) を直接検出する。
public actor DecodedTextChunkReader: ChunkedTextReading {
    private let scalars: String.UnicodeScalarView
    private let respectsCSVQuotes: Bool
    private var currentIndex: String.UnicodeScalarIndex
    private var inQuotes: Bool = false

    public init(text: String, respectsCSVQuotes: Bool = false) {
        scalars = text.unicodeScalars
        self.respectsCSVQuotes = respectsCSVQuotes
        currentIndex = scalars.startIndex
    }

    public func readNextChunk() -> (text: String, isAtEnd: Bool) {
        guard currentIndex < scalars.endIndex else {
            return ("", true)
        }

        var lineCount = 0
        var index = currentIndex

        while index < scalars.endIndex, lineCount < LineChunkReader.linesPerChunk {
            let scalar = scalars[index]
            if respectsCSVQuotes, scalar == "\"" {
                inQuotes.toggle()
            } else if scalar.value == 0x0A, !inQuotes {
                lineCount += 1
            }
            scalars.formIndex(after: &index)
        }

        let chunk = String(scalars[currentIndex ..< index])
        currentIndex = index
        let isAtEnd = currentIndex >= scalars.endIndex
        return (chunk, isAtEnd)
    }
}
