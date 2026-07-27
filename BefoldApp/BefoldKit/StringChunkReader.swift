import Foundation

/// テキストを行単位のチャンクで逐次読み込む抽象(テストでの差し替え用)。
/// AnyObject 要件は呼び出し側がセッションの同一性比較(===)に使う。
public protocol ChunkedTextReading: AnyObject, Sendable {
    /// 次のチャンクと、読み終えたかどうかを返す。
    func readNextChunk() async throws -> (text: String, isAtEnd: Bool)
}

/// チャンクをどこで区切ってよいかの判定方式。
/// ファイル種別ごとに「途中で切ると壊れる構造」が違うため、走査の仕方を分ける。
public enum ChunkBoundary: Sendable {
    /// 行境界だけで区切る軽量パス(コード等)。
    case lines
    /// CSV のクォート内改行を境界にしない。
    case csvQuotes
    /// markdown のブロック境界(コードフェンス外の空行)でのみ区切る。
    case markdownBlocks

    /// ファイル種別に対応する境界。この対応を 1 箇所に集約し、
    /// 読み込み経路ごとに条件が食い違わないようにする。
    public init(fileType: FileType) {
        if fileType.csvDelimiter != nil {
            self = .csvQuotes
        } else if fileType == .markdown {
            self = .markdownBlocks
        } else {
            self = .lines
        }
    }
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
    private let boundary: ChunkBoundary
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
    /// markdown のコードフェンスの内側にいるか。チャンクをまたいで保持する必要があるため
    /// (フェンスがチャンク境界を越えて続くことがある)、読み出しごとにリセットしない。
    private var inFence: Bool = false
    /// 開いているフェンスの記号(0x60 = ` / 0x7E = ~)と連続数。閉じ側の判定に使う。
    private var fenceMarker: UInt8 = 0
    private var fenceLength: Int = 0

    /// boundary はファイル種別ごとの「途中で切ると壊れる構造」に合わせた走査方式。
    /// 種別から決める場合は `ChunkBoundary(fileType:)` を使う。
    public init(cache: NormalizedTextCache, boundary: ChunkBoundary = .lines) {
        self.cache = cache
        self.boundary = boundary
    }

    /// CSV のクォート判定の有無だけを指定する簡易イニシャライザ。
    /// クォート挙動そのものを対象にしたテストで使う。
    public init(cache: NormalizedTextCache, respectsCSVQuotes: Bool) {
        self.init(cache: cache, boundary: respectsCSVQuotes ? .csvQuotes : .lines)
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
        switch boundary {
        case .lines: advanceByLines(from: startOffset)
        case .csvQuotes: advanceRespectingQuotes(from: startOffset)
        case .markdownBlocks: advanceByMarkdownBlocks(from: startOffset)
        }
    }

    /// 1 行分の処理結果。強制分割ならその終端位置、そうでなければ
    /// チャンクの行数上限に数えるか(countsTowardLimit)と、
    /// その行の直後でチャンクを終えてよいか(mayEndHere)を返す。
    ///
    /// この 2 つは一致しないことがある。CSV はクォート内の行を「数えないし切れない」
    /// として扱えるが、markdown は「全行を数えるが切れるのは空行だけ」であり、
    /// 行数上限に達しても安全な境界が来るまで待つ必要がある。
    private enum LineOutcome {
        case forcedSplit(endOffset: Int)
        case consumed(countsTowardLimit: Bool, mayEndHere: Bool)
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
            case let .consumed(countsTowardLimit, mayEndHere):
                scanLine += 1
                lineStart = lineEnd
                if countsTowardLimit { linesConsumed += 1 }
                if linesConsumed >= Self.linesPerChunk, mayEndHere {
                    return (lineEnd, scanLine, false)
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
            return .consumed(countsTowardLimit: true, mayEndHere: true)
        }
    }

    /// markdown のブロック境界だけで区切る走査パス。
    /// コードフェンスの内側と段落の途中では終わらせず、フェンス外の空行でのみ終える。
    /// 行の分類は先頭の空白とフェンス記号だけを見るため、CSV のような全バイト走査にはならない。
    private func advanceByMarkdownBlocks(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
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
            return .consumed(countsTowardLimit: true, mayEndHere: kind == .blank && !inFence)
        }
    }

    /// markdown の行種別。境界判定に必要な最小限だけを見る。
    private enum MarkdownLineKind: Equatable {
        case blank
        /// ``` / ~~~ で始まる行。marker はその記号、length は連続数。
        case fence(marker: UInt8, length: Int)
        case text
    }

    /// 行頭の空白を読み飛ばし、空行かコードフェンスかそれ以外かを判定する。
    private func classifyMarkdownLine(from lineStart: Int, to lineEnd: Int) -> MarkdownLineKind {
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

    /// フェンスの開閉状態を更新する。閉じ側は開いた記号と同じで、かつ
    /// 開いたときと同じ長さ以上でなければ閉じない(CommonMark の規則)。
    private func applyFenceTransition(_ kind: MarkdownLineKind) {
        guard case let .fence(marker, length) = kind else { return }
        if inFence {
            if marker == fenceMarker, length >= fenceLength {
                inFence = false
                fenceMarker = 0
                fenceLength = 0
            }
        } else {
            inFence = true
            fenceMarker = marker
            fenceLength = length
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

            // クォート内の行は数えず、そこでチャンクを終えることもしない。
            let outsideQuotedField = !inQuotes || hasGivenUpQuoteTracking
            return .consumed(countsTowardLimit: outsideQuotedField, mayEndHere: outsideQuotedField)
        }
    }
}
