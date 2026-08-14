import Foundation

/// markdown のコードフェンス状態。チャンクをまたいで持ち越す必要があるため
/// StringChunkReader の stored property として保持されるが、遷移規則はここに閉じる。
struct MarkdownFenceState {
    /// フェンスの内側にいるか。
    private(set) var isInside = false
    /// 開いているフェンスの記号(0x60 = ` / 0x7E = ~)。
    private var marker: UInt8 = 0
    /// 開いたフェンスの記号の連続数。閉じ側はこれ以上の長さが必要。
    private var length = 0

    /// フェンス行を 1 行読んだときの状態遷移。閉じ側は開いた記号と同じで、かつ
    /// 開いたときと同じ長さ以上でなければ閉じない(CommonMark の規則)。
    mutating func apply(marker newMarker: UInt8, length newLength: Int) {
        if isInside {
            if newMarker == marker, newLength >= length {
                isInside = false
                marker = 0
                length = 0
            }
        } else {
            isInside = true
            marker = newMarker
            length = newLength
        }
    }
}

/// ChunkBoundary.markdownBlocks の走査戦略。
extension StringChunkReader {
    /// markdown のブロック境界だけで区切る走査パス。
    /// コードフェンスの内側と段落の途中では終わらせず、フェンス外の空行でのみ終える。
    /// 行の分類は先頭の空白とフェンス記号だけを見るため、CSV のような全バイト走査にはならない。
    func advanceByMarkdownBlocks(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
        scanLines(from: startOffset) { lineStart, lineEnd, bytesScanned in
            let lineBytes = lineEnd - lineStart
            // 空行を探して際限なく伸びないよう、バイト上限は境界判定より優先する。
            if bytesScanned + lineBytes >= Self.maxChunkBytes {
                let rawEnd = lineStart + (Self.maxChunkBytes - bytesScanned)
                let forcedEnd = cache.snappedToCharacterBoundary(rawEnd, lowerBound: lineStart)
                return .forcedSplit(endOffset: forcedEnd)
            }
            bytesScanned += lineBytes
            let kind = classifyMarkdownLine(from: lineStart, to: lineEnd)
            applyFenceTransition(kind)
            return .consumed(countsTowardLimit: true, mayEndHere: kind == .blank && !markdownFence.isInside)
        }
    }

    /// markdown の行種別。境界判定に必要な最小限だけを見る。
    enum MarkdownLineKind: Equatable {
        case blank
        /// ``` / ~~~ で始まる行。marker はその記号、length は連続数。
        case fence(marker: UInt8, length: Int)
        case text
    }

    /// 行頭の空白を読み飛ばし、空行かコードフェンスかそれ以外かを判定する。
    func classifyMarkdownLine(from lineStart: Int, to lineEnd: Int) -> MarkdownLineKind {
        var cursor = lineStart
        while cursor < lineEnd {
            let byte = cache.normalizedByte(at: cursor)
            if byte == 0x20 || byte == 0x09 { cursor += 1 } else { break }
        }
        guard cursor < lineEnd else { return .blank }

        let first = cache.normalizedByte(at: cursor)
        if first == 0x0A || first == 0x0D { return .blank }

        // ` (0x60) と ~ (0x7E) はどちらも ASCII のため、マルチバイト文字の
        // 継続バイト(0x80 以上)と衝突せずバイト単位で数えられる。
        guard first == 0x60 || first == 0x7E else { return .text }
        var length = 0
        while cursor < lineEnd, cache.normalizedByte(at: cursor) == first {
            length += 1
            cursor += 1
        }
        return length >= 3 ? .fence(marker: first, length: length) : .text
    }

    /// フェンスの開閉状態を更新する。遷移規則は MarkdownFenceState 側に持つ。
    func applyFenceTransition(_ kind: MarkdownLineKind) {
        guard case let .fence(marker, length) = kind else { return }
        markdownFence.apply(marker: marker, length: length)
    }
}
