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
/// cache は正規化を必要な範囲まで増分的にしか行っていない場合があるため(NormalizedTextCache の
/// normalizeFully: false)、走査前に ensureNormalized で 1 チャンク分の先読みを都度要求する。
public actor StringChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000
    /// 不平衡クォートや改行なし巨大行でも 1 チャンクが際限なく肥大化しないための強制分割の上限。
    public static let maxChunkBytes = 1 * 1024 * 1024
    /// クォート付き CSV フィールドとして正当に扱う最大バイト数。開いたクォートが
    /// これを超えて閉じられない場合は不均衡クォートの可能性が高いとみなし、
    /// hasGivenUpQuoteTracking を立てて行ベースのチャンク区切りを再開する。
    /// チャンク境界(maxChunkBytes)とは無関係の、CSV セルの実長に基づく閾値。
    private static let maxQuotedFieldBytes = 500

    private var cache: NormalizedTextCache
    private let respectsCSVQuotes: Bool
    private var currentLine: Int = 0
    /// バイト上限による強制分割で行の途中まで消費した場合の再開位置(normalizedBytes 内オフセット)。
    /// 行境界で自然に終わったチャンクの後は nil に戻る。
    private var resumeOffset: Int?
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
        // まず currentLine の開始位置が判明する(もしくは真に末尾に達している)ところまで
        // 正規化する。バイト数の下限は課さない(行が見つかり次第 or 真の末尾で止めてよい)。
        cache.ensureNormalized(minimumLineCount: currentLine + 1, minimumByteCount: .max)

        guard currentLine < cache.lineCount || resumeOffset != nil else {
            return ("", true)
        }

        let startOffset = resumeOffset ?? cache.lineStart(currentLine)
        // 1 チャンク分(linesPerChunk 行 or maxChunkBytes バイト)を走査し切れるだけの
        // 範囲を追加正規化する。どちらかの上限に達するか、ファイル全体を正規化し終えた時点で
        // 十分なので、両方を満たす必要はない。
        cache.ensureNormalized(
            minimumLineCount: currentLine + Self.linesPerChunk + 1,
            minimumByteCount: startOffset + Self.maxChunkBytes
        )

        let (endOffset, endLine, forcedSplit) = advance(from: startOffset)
        let chunk = cache.chunkText(startOffset ..< endOffset)

        // endLine は forcedSplit の場合も resumeOffset が実際に属する行を指すため、
        // 次回 advance(from:) が正しい行境界(lineStart(currentLine+1))を参照できるよう常に更新する。
        currentLine = endLine

        // forcedSplit はバイト上限で「行の途中」を想定したフラグだが、テキスト長が
        // ちょうど maxChunkBytes で終わる(末尾改行なし)場合は endOffset が正規化済み末尾と
        // 一致する。この場合は forcedSplit の値によらず読み切ったとみなす
        // (ファイル全体を正規化し終えていない間は、正規化済み末尾はまだ本当の末尾ではない)。
        let isAtEnd = cache.isFullyNormalized && endOffset == cache.normalizedByteCount
        resumeOffset = (forcedSplit && !isAtEnd) ? endOffset : nil

        return (chunk, isAtEnd)
    }

    /// startOffset から走査し、行数上限(linesPerChunk)とバイト上限(maxChunkBytes)の
    /// どちらか早い方でチャンク終端を決める。バイト上限による終端(forcedSplit)は
    /// 行境界を跨がず途中で切れるため、呼び出し側は次回 resumeOffset から再開する。
    private func advance(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
        respectsCSVQuotes
            ? advanceRespectingQuotes(from: startOffset)
            : advanceByLines(from: startOffset)
    }

    /// 1 行分の処理結果。強制分割ならその終端位置、そうでなければ
    /// その行を linesConsumed に数えるかどうかを返す。
    private enum LineOutcome {
        case forcedSplit(endOffset: Int)
        case consumed(shouldCountLine: Bool)
    }

    /// advanceByLines と advanceRespectingQuotes に共通する行境界の走査骨格。
    /// 行末位置(lineStart/lineEnd)の算出・scanLine の進行・linesPerChunk 到達判定・
    /// 走査終了時の return は両者で同一のため、行ごとの中身(processLine)だけを
    /// 差し替え可能にして共通化する。
    private func scanLines(
        from startOffset: Int,
        processLine: (_ lineStart: Int, _ lineEnd: Int, _ bytesScanned: inout Int) -> LineOutcome
    ) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
        var scanLine = currentLine
        var lineStart = startOffset
        var linesConsumed = 0
        var bytesScanned = 0

        while scanLine < cache.lineCount {
            let lineEnd = scanLine + 1 < cache.lineCount
                ? cache.lineStart(scanLine + 1)
                : cache.normalizedByteCount

            switch processLine(lineStart, lineEnd, &bytesScanned) {
            case let .forcedSplit(endOffset):
                return (endOffset, scanLine, true)
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
    /// 行境界は lineStart(_:) から O(1) で参照でき、バイト単位の走査は
    /// maxChunkBytes 境界を跨ぐ行の強制分割時のみ行う。
    private func advanceByLines(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
        scanLines(from: startOffset) { lineStart, lineEnd, bytesScanned in
            let lineBytes = lineEnd - lineStart
            if bytesScanned + lineBytes >= Self.maxChunkBytes {
                let rawEnd = lineStart + (Self.maxChunkBytes - bytesScanned)
                let forcedEnd = cache.snappedToCharacterBoundary(rawEnd, lowerBound: lineStart)
                return .forcedSplit(endOffset: forcedEnd)
            }
            bytesScanned += lineBytes
            return .consumed(shouldCountLine: true)
        }
    }

    /// CSV クォート内の改行をチャンク境界にしないための、UTF-8 バイト単位の走査パス。
    /// クォートの対応を追う都合上、行の中身をバイト単位で読む必要がある。
    private func advanceRespectingQuotes(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
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

            return .consumed(shouldCountLine: !inQuotes || hasGivenUpQuoteTracking)
        }
    }
}
