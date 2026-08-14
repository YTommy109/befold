import Foundation

/// ChunkBoundary.lines の走査戦略。行境界だけでチャンクを区切る軽量パス。
extension StringChunkReader {
    /// CSV クォートを判定しないパス。クォートの対応関係を追う必要がないため、
    /// 行境界は lineStart(_:) から O(1) で参照でき、バイト単位の走査は
    /// maxChunkBytes 境界を跨ぐ行の強制分割時のみ行う。
    func advanceByLines(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
        scanLines(from: startOffset) { lineStart, lineEnd, bytesScanned in
            let lineBytes = lineEnd - lineStart
            if bytesScanned + lineBytes >= Self.maxChunkBytes {
                let rawEnd = lineStart + (Self.maxChunkBytes - bytesScanned)
                let forcedEnd = cache.snappedToCharacterBoundary(rawEnd, lowerBound: lineStart)
                return .forcedSplit(endOffset: forcedEnd)
            }
            bytesScanned += lineBytes
            return .consumed(countsTowardLimit: true, mayEndHere: true)
        }
    }
}
