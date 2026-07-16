import Foundation

public actor StringChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000

    private let cache: NormalizedTextCache
    private let respectsCSVQuotes: Bool
    private var currentLine: Int = 0
    private var inQuotes: Bool = false

    public init(cache: NormalizedTextCache, respectsCSVQuotes: Bool = false) {
        self.cache = cache
        self.respectsCSVQuotes = respectsCSVQuotes
    }

    public func readNextChunk() -> (text: String, isAtEnd: Bool) {
        guard currentLine < cache.lineCount else {
            return ("", true)
        }

        let startIndex = cache.lineStartIndices[currentLine]

        let endLine = if respectsCSVQuotes {
            advanceRespectingQuotes()
        } else {
            min(currentLine + Self.linesPerChunk, cache.lineCount)
        }

        let endIndex = if endLine < cache.lineCount {
            cache.lineStartIndices[endLine]
        } else {
            cache.text.endIndex
        }
        let chunk = String(cache.text[startIndex ..< endIndex])
        currentLine = endLine
        return (chunk, currentLine >= cache.lineCount)
    }

    private func advanceRespectingQuotes() -> Int {
        var linesConsumed = 0
        var scanLine = currentLine

        while scanLine < cache.lineCount {
            let lineStart = cache.lineStartIndices[scanLine]
            let lineEnd = scanLine + 1 < cache.lineCount
                ? cache.lineStartIndices[scanLine + 1]
                : cache.text.endIndex

            for char in cache.text[lineStart ..< lineEnd] where char == "\"" {
                inQuotes.toggle()
            }

            scanLine += 1

            if !inQuotes {
                linesConsumed += 1
                if linesConsumed >= Self.linesPerChunk {
                    break
                }
            }
        }

        return scanLine
    }
}
