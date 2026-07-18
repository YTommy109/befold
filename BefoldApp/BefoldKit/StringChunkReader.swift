import Foundation

/// テキストを行単位のチャンクで逐次読み込む抽象(テストでの差し替え用)。
/// AnyObject 要件は呼び出し側がセッションの同一性比較(===)に使う。
public protocol ChunkedTextReading: AnyObject, Sendable {
    /// 次のチャンクと、読み終えたかどうかを返す。
    func readNextChunk() async throws -> (text: String, isAtEnd: Bool)
}

/// NormalizedTextCache から行単位のチャンクを逐次読み出す ChunkedTextReading の標準実装。
/// CSV クォート内の改行をチャンク境界にしない任意対応と、巨大行でもチャンクが際限なく
/// 肥大化しないためのバイト単位の強制分割を備える。
public actor StringChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000
    /// 不平衡クォートや改行なし巨大行でも 1 チャンクが際限なく肥大化しないための強制分割の上限。
    public static let maxChunkBytes = 1 * 1024 * 1024
    /// クォート付き CSV フィールドとして正当に扱う最大バイト数。開いたクォートが
    /// これを超えて閉じられない場合は不均衡クォートの可能性が高いとみなし、
    /// hasGivenUpQuoteTracking を立てて行ベースのチャンク区切りを再開する。
    /// チャンク境界(maxChunkBytes)とは無関係の、CSV セルの実長に基づく閾値。
    private static let maxQuotedFieldBytes = 500

    private let cache: NormalizedTextCache
    private let respectsCSVQuotes: Bool
    private var currentLine: Int = 0
    /// バイト上限による強制分割で行の途中まで消費した場合の再開位置。
    /// 行境界で自然に終わったチャンクの後は nil に戻る。
    private var resumeIndex: String.Index?
    private var inQuotes: Bool = false
    /// 現在開いているクォートが閉じずに経過したバイト数。クォートの開閉ごとに 0 へ戻る。
    private var quotedRunLength: Int = 0
    /// quotedRunLength が maxQuotedFieldBytes を超え、行ベースのチャンク区切りを
    /// 再開すると判断した状態。inQuotes 自体は書き換えない(実際のクォート対応関係を
    /// 壊さないため)ので、本物の閉じクォートに出会えば toggle 処理が inQuotes を
    /// 正しく false に戻し、このフラグもあわせてリセットされる。
    private var hasGivenUpQuoteTracking: Bool = false

    /// respectsCSVQuotes が true の場合、CSV のクォート内改行をチャンク境界にしない
    /// (advanceRespectingQuotes を使う)。false の場合は行境界のみで判定する軽量パスを使う。
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
        respectsCSVQuotes
            ? advanceRespectingQuotes(from: startIndex)
            : advanceByLines(from: startIndex)
    }

    /// 1 行分の処理結果。強制分割ならその終端位置、そうでなければ
    /// その行を linesConsumed に数えるかどうかを返す。
    private enum LineOutcome {
        case forcedSplit(endIndex: String.Index)
        case consumed(shouldCountLine: Bool)
    }

    /// advanceByLines と advanceRespectingQuotes に共通する行境界の走査骨格。
    /// 行末位置(lineStart/lineEnd)の算出・scanLine の進行・linesPerChunk 到達判定・
    /// 走査終了時の return は両者で同一のため、行ごとの中身(processLine)だけを
    /// 差し替え可能にして共通化する。
    private func scanLines(
        from startIndex: String.Index,
        processLine: (_ lineStart: String.Index, _ lineEnd: String.Index, _ bytesScanned: inout Int) -> LineOutcome
    ) -> (endIndex: String.Index, endLine: Int, forcedSplit: Bool) {
        var scanLine = currentLine
        var lineStart = startIndex
        var linesConsumed = 0
        var bytesScanned = 0

        while scanLine < cache.lineCount {
            let lineEnd = scanLine + 1 < cache.lineCount
                ? cache.lineStartIndices[scanLine + 1]
                : cache.text.endIndex

            switch processLine(lineStart, lineEnd, &bytesScanned) {
            case let .forcedSplit(endIndex):
                return (endIndex, scanLine, true)
            case let .consumed(shouldCountLine):
                scanLine += 1
                lineStart = lineEnd
                if shouldCountLine {
                    linesConsumed += 1
                    if linesConsumed >= Self.linesPerChunk {
                        return (lineEnd, scanLine, false)
                    }
                }
            }
        }

        return (lineStart, scanLine, false)
    }

    /// CSV クォートを判定しないパス。クォートの対応関係を追う必要がないため、
    /// 行境界は lineStartIndices から O(1) で参照でき、バイト単位の走査は
    /// maxChunkBytes 境界を跨ぐ行の強制分割時のみ行う。
    private func advanceByLines(from startIndex: String
        .Index) -> (endIndex: String.Index, endLine: Int, forcedSplit: Bool)
    {
        let utf8View = cache.text.utf8
        return scanLines(from: startIndex) { lineStart, lineEnd, bytesScanned in
            let lineBytes = utf8View.distance(from: lineStart, to: lineEnd)
            if bytesScanned + lineBytes >= Self.maxChunkBytes {
                let rawEnd = utf8View.index(lineStart, offsetBy: Self.maxChunkBytes - bytesScanned)
                let forcedEnd = Self.snappedToCharacterBoundary(rawEnd, lowerBound: lineStart, in: utf8View)
                return .forcedSplit(endIndex: forcedEnd)
            }
            bytesScanned += lineBytes
            return .consumed(shouldCountLine: true)
        }
    }

    /// UTF-8 継続バイト(0x80–0xBF)の途中を指している場合、そのマルチバイト文字の
    /// 先頭バイトまで後退させる。バイト数上限による強制分割はバイト単位の位置計算を
    /// 経由するため、文字境界を保証するにはこのスナップが必須。
    private static func snappedToCharacterBoundary(
        _ index: String.Index,
        lowerBound: String.Index,
        in utf8View: String.UTF8View
    ) -> String.Index {
        var index = index
        while index > lowerBound, index < utf8View.endIndex, (0x80 ... 0xBF).contains(utf8View[index]) {
            index = utf8View.index(before: index)
        }
        return index
    }

    /// CSV クォート内の改行をチャンク境界にしないための、UTF-8 バイト単位の走査パス。
    /// クォートの対応を追う都合上、行の中身をバイト単位で読む必要がある。
    private func advanceRespectingQuotes(from startIndex: String
        .Index) -> (endIndex: String.Index, endLine: Int, forcedSplit: Bool)
    {
        let utf8View = cache.text.utf8
        return scanLines(from: startIndex) { lineStart, lineEnd, bytesScanned in
            // クォート判定を含むこのループはホットパス(巨大CSV全行)のため、書記素クラスタ
            // 境界計算を伴う Character 単位ではなく UTF-8 バイト単位で走査する。`"` (U+0022) は
            // ASCII のためマルチバイト文字の継続バイト(0x80 以上)と衝突せず、バイト走査でも
            // Character 走査と同じ判定結果になる。
            var cursor = lineStart
            while cursor < lineEnd {
                let byte = utf8View[cursor]
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
                cursor = utf8View.index(after: cursor)

                if bytesScanned >= Self.maxChunkBytes {
                    let forcedEnd = Self.snappedToCharacterBoundary(cursor, lowerBound: lineStart, in: utf8View)
                    if inQuotes, forcedEnd < cursor {
                        // snappedToCharacterBoundary が巻き戻したバイトは次回の
                        // resumeIndex から再走査されるため、quotedRunLength から
                        // 差し引いて二重カウントを防ぐ。
                        let rolledBackBytes = utf8View.distance(from: forcedEnd, to: cursor)
                        quotedRunLength = max(0, quotedRunLength - rolledBackBytes)
                        if quotedRunLength <= Self.maxQuotedFieldBytes {
                            hasGivenUpQuoteTracking = false
                        }
                    }
                    return .forcedSplit(endIndex: forcedEnd)
                }
            }

            return .consumed(shouldCountLine: !inQuotes || hasGivenUpQuoteTracking)
        }
    }
}
