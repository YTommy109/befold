import Foundation

/// ChunkBoundary.csvQuotes の走査戦略。CSV のクォート内改行を境界にしない。
extension StringChunkReader {
    /// クォート付き CSV フィールドとして正当に扱う最大バイト数。開いたクォートが
    /// これを超えて閉じられない場合は不均衡クォートの可能性が高いとみなし、
    /// hasGivenUpQuoteTracking を立てて行ベースのチャンク区切りを再開する。
    /// チャンク境界(maxChunkBytes)とは無関係の、CSV セルの実長に基づく閾値。
    private static let maxQuotedFieldBytes = 500

    /// CSV クォート内の改行をチャンク境界にしないための、UTF-8 バイト単位の走査パス。
    /// クォートの対応を追う都合上、行の中身をバイト単位で読む必要がある。
    func advanceRespectingQuotes(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
        scanLines(from: startOffset) { lineStart, lineEnd, bytesScanned in
            // クォート判定を含むこのループはホットパス(巨大CSV全行)のため、書記素クラスタ
            // 境界計算を伴う Character 単位ではなく UTF-8 バイト単位で走査する。`"` (U+0022) は
            // ASCII のためマルチバイト文字の継続バイト(0x80 以上)と衝突せず、バイト走査でも
            // Character 走査と同じ判定結果になる。
            var cursor = lineStart
            while cursor < lineEnd {
                let byte = cache.normalizedByte(at: cursor)
                if byte == 0x22 {
                    // 本物の閉じクォートが見つかった場合、対応関係を正しく戻す。
                    // (途中で hasGivenUpQuoteTracking が立っていても inQuotes 自体は
                    // 書き換えていないため、ここでの toggle は常に正しい状態遷移になる。)
                    inQuotes.toggle()
                    quotedRunLength = 0
                    hasGivenUpQuoteTracking = false
                } else if inQuotes {
                    quotedRunLength += 1
                    if quotedRunLength > Self.maxQuotedFieldBytes {
                        // 不均衡クォートの可能性が高いとみなし、行ベースの分割を再開する。
                        // inQuotes は書き換えない(実際のクォートが後で閉じたときに
                        // 誤って反転させないため)。
                        hasGivenUpQuoteTracking = true
                        quotedRunLength = 0
                    }
                }
                bytesScanned += 1
                cursor += 1

                if bytesScanned >= Self.maxChunkBytes {
                    let forcedEnd = cache.snappedToCharacterBoundary(cursor, lowerBound: lineStart)
                    if inQuotes, forcedEnd < cursor {
                        // snappedToCharacterBoundary が巻き戻したバイトは次回の
                        // resumeOffset から再走査されるため、quotedRunLength から
                        // 差し引いて二重カウントを防ぐ。
                        let rolledBackBytes = cursor - forcedEnd
                        quotedRunLength = max(0, quotedRunLength - rolledBackBytes)
                        if quotedRunLength <= Self.maxQuotedFieldBytes {
                            hasGivenUpQuoteTracking = false
                        }
                    }
                    return .forcedSplit(endOffset: forcedEnd)
                }
            }

            // クォート内の行は数えず、そこでチャンクを終えることもしない。
            let outsideQuotedField = !inQuotes || hasGivenUpQuoteTracking
            return .consumed(countsTowardLimit: outsideQuotedField, mayEndHere: outsideQuotedField)
        }
    }
}
