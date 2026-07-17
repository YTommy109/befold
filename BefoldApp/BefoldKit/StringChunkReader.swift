import Foundation

/// テキストを行単位のチャンクで逐次読み込む抽象(テストでの差し替え用)。
/// AnyObject 要件は呼び出し側がセッションの同一性比較(===)に使う。
public protocol ChunkedTextReading: AnyObject, Sendable {
    /// 次のチャンクと、読み終えたかどうかを返す。
    func readNextChunk() async throws -> (text: String, isAtEnd: Bool)
}

public actor StringChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000
    /// 不平衡クォートや改行なし巨大行でも 1 チャンクが際限なく肥大化しないための強制分割の上限。
    public static let maxChunkBytes = 1 * 1024 * 1024

    private let cache: NormalizedTextCache
    private let respectsCSVQuotes: Bool
    private var currentLine: Int = 0
    /// バイト上限による強制分割で行の途中まで消費した場合の再開位置。
    /// 行境界で自然に終わったチャンクの後は nil に戻る。
    private var resumeIndex: String.Index?
    private var inQuotes: Bool = false

    public init(cache: NormalizedTextCache, respectsCSVQuotes: Bool = false) {
        self.cache = cache
        self.respectsCSVQuotes = respectsCSVQuotes
    }

    public func readNextChunk() -> (text: String, isAtEnd: Bool) {
        guard currentLine < cache.lineCount || resumeIndex != nil else {
            return ("", true)
        }

        let startIndex = resumeIndex ?? cache.lineStartIndices[currentLine]
        let (endIndex, endLine, forcedSplit) = advance(from: startIndex)
        let chunk = String(cache.text[startIndex ..< endIndex])

        // endLine は forcedSplit の場合も resumeIndex が実際に属する行を指すため、
        // 次回 advance(from:) が正しい行境界(lineStartIndices[currentLine+1])を参照できるよう常に更新する。
        currentLine = endLine
        if forcedSplit {
            resumeIndex = endIndex
            // 強制分割時点でのクォート状態は行途中の恣意的な切断点でのものでしかなく、
            // 以降ずっと inQuotes=true のまま全チャンクが強制分割に陥る連鎖を防ぐためリセットする。
            inQuotes = false
        } else {
            resumeIndex = nil
        }

        let isAtEnd = !forcedSplit && currentLine >= cache.lineCount
        return (chunk, isAtEnd)
    }

    /// startIndex から走査し、行数上限(linesPerChunk)とバイト上限(maxChunkBytes)の
    /// どちらか早い方でチャンク終端を決める。バイト上限による終端(forcedSplit)は
    /// 行境界を跨がず途中で切れるため、呼び出し側は次回 resumeIndex から再開する。
    private func advance(from startIndex: String.Index) -> (endIndex: String.Index, endLine: Int, forcedSplit: Bool) {
        var scanLine = currentLine
        var lineStart = startIndex
        var linesConsumed = 0
        var bytesScanned = 0

        while scanLine < cache.lineCount {
            let lineEnd = scanLine + 1 < cache.lineCount
                ? cache.lineStartIndices[scanLine + 1]
                : cache.text.endIndex

            var cursor = lineStart
            while cursor < lineEnd {
                let char = cache.text[cursor]
                if respectsCSVQuotes, char == "\"" {
                    inQuotes.toggle()
                }
                bytesScanned += char.utf8.count
                cursor = cache.text.index(after: cursor)

                if bytesScanned >= Self.maxChunkBytes {
                    return (cursor, scanLine, true)
                }
            }

            scanLine += 1
            lineStart = lineEnd

            if !inQuotes {
                linesConsumed += 1
                if linesConsumed >= Self.linesPerChunk {
                    return (lineEnd, scanLine, false)
                }
            }
        }

        return (lineStart, scanLine, false)
    }
}
