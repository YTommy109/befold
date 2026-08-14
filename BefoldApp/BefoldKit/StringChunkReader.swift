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

    /// 走査対象の正規化バイト列。戦略ごとの extension(+Lines / +Markdown / +Quotes)から
    /// 参照するため internal。外部には公開しない。
    var cache: NormalizedTextCache
    private let boundary: ChunkBoundary
    /// 次に読み出す行。scanLines(from:processLine:) の走査開始位置として戦略側からも読む。
    var currentLine: Int = 0
    /// バイト上限による強制分割で行の途中まで消費した場合の再開位置(normalizedBytes 内オフセット)。
    /// 行境界で自然に終わったチャンクの後は nil に戻る。
    private var resumeOffset: Int?
    /// 以下 3 つは CSV クォート走査の状態。stored property は extension に置けないため
    /// 型本体に残すが、読み書きするのは StringChunkReader+Quotes だけ。
    var inQuotes: Bool = false
    /// 現在開いているクォートが閉じずに経過したバイト数。クォートの開閉ごとに 0 へ戻る。
    var quotedRunLength: Int = 0
    /// quotedRunLength が maxQuotedFieldBytes を超え、行ベースのチャンク区切りを
    /// 再開すると判断した状態。inQuotes 自体は書き換えない(実際のクォート対応関係を
    /// 壊さないため)ので、本物の閉じクォートに出会えば toggle 処理が inQuotes を
    /// 正しく false に戻し、このフラグもあわせてリセットされる。
    var hasGivenUpQuoteTracking: Bool = false
    /// markdown のコードフェンス状態。チャンクをまたいで保持する必要があるため
    /// (フェンスがチャンク境界を越えて続くことがある)、読み出しごとにリセットしない。
    ///
    /// stored property は extension に宣言できないため、状態そのものを
    /// StringChunkReader+Markdown 側へ完全に閉じることはできない。代わりに
    /// 中身と遷移規則を MarkdownFenceState(同ファイルで宣言)へ寄せ、本体に残る面を
    /// この 1 プロパティに限っている。読み書きするのは +Markdown だけ。
    var markdownFence = MarkdownFenceState()

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
    func advance(from startOffset: Int) -> (endOffset: Int, endLine: Int, forcedSplit: Bool) {
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
    enum LineOutcome {
        case forcedSplit(endOffset: Int)
        case consumed(countsTowardLimit: Bool, mayEndHere: Bool)
    }

    /// advanceByLines と advanceRespectingQuotes に共通する行境界の走査骨格。
    /// 行末位置(lineStart/lineEnd)の算出・scanLine の進行・linesPerChunk 到達判定・
    /// 走査終了時の return は両者で同一のため、行ごとの中身(processLine)だけを
    /// 差し替え可能にして共通化する。
    func scanLines(
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
}
