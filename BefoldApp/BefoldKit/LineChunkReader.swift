import Foundation

/// テキストを行単位のチャンクで逐次読み込む抽象(テストでの差し替え用)。
/// AnyObject 要件は呼び出し側がセッションの同一性比較(===)に使う。
public protocol ChunkedTextReading: AnyObject, Sendable {
    /// 次のチャンクと、読み終えたかどうかを返す。
    func readNextChunk() async throws -> (text: String, isAtEnd: Bool)
}

/// ファイルを行単位のチャンク(既定 1000 行 / 最大 1MB)で逐次読み込む actor。
/// I/O・デコードを呼び出し元のアクター(メインスレッド)から切り離して実行する。
/// UTF-8/ASCII に加え Shift_JIS / EUC-JP 等のレガシーエンコーディングにも対応する。
/// UTF-16 / UTF-32 は改行バイト(0x0A/0x0D)が多バイト列中に出現し
/// バイト走査で行境界を確定できないため `unsupportedForChunking` を投げる。
public actor LineChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000
    public static let maxChunkBytes = 1 * 1024 * 1024

    private var isAtEnd = false

    private let handle: FileHandle
    private let encoding: String.Encoding
    private let bomLength: Int
    private let respectsCSVQuotes: Bool
    private var offset: UInt64
    private var remainder = Data()
    /// RFC 4180 の引用符状態。通常の分割は引用符外の改行直後で行われるため常に false だが、
    /// maxChunkBytes による強制分割では引用フィールドの途中で切れることがあり、
    /// 次回の readNextChunk へ状態を持ち越す必要がある。
    private var inQuotes = false

    /// - Parameter respectsCSVQuotes: true の場合、RFC 4180 の引用符状態を追跡し、
    ///   引用フィールド内の改行をチャンク分割候補として数えない
    ///   (JS 側の CSV トークナイザがチャンク単体でパースしても壊れないようにする)。
    ///
    /// nonisolated な同期 init のため、格納済みプロパティの読み出しはできない。
    /// エンコーディング判定はローカル値で行い、最後に書き込みだけを行う。
    public init(url: URL, respectsCSVQuotes: Bool = false) throws {
        self.respectsCSVQuotes = respectsCSVQuotes
        let handle = try FileHandle(forReadingFrom: url)
        self.handle = handle

        guard let probe = try handle.read(upToCount: TextEncoding.sniffLength), !probe.isEmpty else {
            encoding = .utf8
            bomLength = 0
            offset = 0
            isAtEnd = true
            return
        }

        guard TextEncoding.isChunkableEncoding(probe) else {
            try? handle.close()
            throw TextEncodingError.unsupportedForChunking
        }

        // プローブが満杯(= ファイル途中で切れている可能性がある)なら、8192 バイト目が
        // マルチバイト文字を跨いで UTF-8 判定に失敗しないよう文字境界まで切り詰める。
        // 短いプローブの末尾は実際のファイル末尾なので切り詰めない
        // (不正な UTF-8 は判定に失敗させる)。
        let detectionProbe = probe.count == TextEncoding.sniffLength
            ? TextEncoding.trimIncompleteUTF8Tail(probe)
            : probe

        let detectedEncoding: String.Encoding
        let detectedBomLength: Int
        if let bom = TextEncoding.detectBOM(detectionProbe) {
            detectedEncoding = bom.encoding
            detectedBomLength = bom.bomLength
        } else if let detected = TextEncoding.detectEncoding(detectionProbe) {
            detectedEncoding = detected
            detectedBomLength = 0
        } else {
            detectedEncoding = .utf8
            detectedBomLength = 0
        }

        try handle.seek(toOffset: UInt64(detectedBomLength))
        encoding = detectedEncoding
        bomLength = detectedBomLength
        offset = UInt64(detectedBomLength)
    }

    deinit {
        try? handle.close()
    }

    public func readNextChunk() throws -> (text: String, isAtEnd: Bool) {
        guard !isAtEnd else { return ("", true) }

        var buffer = remainder
        remainder = Data()
        let bytesToRead = Self.maxChunkBytes - buffer.count
        if bytesToRead > 0, let fresh = try handle.read(upToCount: bytesToRead) {
            buffer.append(fresh)
        }

        if buffer.isEmpty {
            isAtEnd = true
            return ("", true)
        }

        let filledBuffer = buffer.count >= Self.maxChunkBytes

        // 引用符状態(quoted)を追跡しつつ改行を数える。UTF-8 では継続バイト・先頭バイトが
        // いずれも 0x80 以上のため、生の 0x22 は常に ASCII の引用符と同一視できる。
        var lineCount = 0
        var splitIndex: Data.Index?
        var quoted = inQuotes
        for index in buffer.indices {
            let byte = buffer[index]
            if respectsCSVQuotes, byte == 0x22 {
                quoted.toggle()
                continue
            }
            if byte == 0x0A, !quoted {
                lineCount += 1
                if lineCount >= Self.linesPerChunk {
                    splitIndex = buffer.index(after: index)
                    break
                }
            } else if byte == 0x0D, !quoted {
                // CR のみ改行(CRLF は 0x0A 分岐で処理済み)。
                let nextIndex = buffer.index(after: index)
                if nextIndex >= buffer.endIndex || buffer[nextIndex] != 0x0A {
                    lineCount += 1
                    if lineCount >= Self.linesPerChunk {
                        splitIndex = nextIndex
                        break
                    }
                }
            }
        }
        // 分割位置で break した場合は引用符外の改行直後なので quoted は false。
        // 末尾まで走査した場合は、強制分割で切り落とす末尾は継続バイト(≥ 0x80)のみで
        // 引用符を含まないため、バッファ全体の走査結果を消費バイト分の状態として使える。
        inQuotes = quoted

        let chunkData: Data
        if let splitIndex {
            chunkData = buffer[buffer.startIndex ..< splitIndex]
            remainder = Data(buffer[splitIndex...])
            isAtEnd = remainder.isEmpty && peekAtEnd()
        } else if !filledBuffer {
            // 改行が linesPerChunk に達しないままファイル末尾に到達した。
            chunkData = buffer
            isAtEnd = true
        } else {
            // 改行が現れないまま maxChunkBytes を満たした(超長行)。
            // マルチバイト文字を割らないよう文字境界で切り詰めて分割する。
            chunkData = TextEncoding.trimIncompleteTail(buffer, encoding: encoding)
            remainder = Data(buffer[chunkData.endIndex...])
            isAtEnd = false
            // 1MB 超の RFC 4180 引用フィールドは現実的に存在しない。
            // 対のない引用符で立ちっぱなしになった状態をここでリセットし、
            // 以降のチャンクが全て強制分割に陥る連鎖を防ぐ。
            inQuotes = false
        }

        guard let text = String(data: chunkData, encoding: encoding) else {
            throw TextEncodingError.decodeFailed
        }
        return (text, isAtEnd)
    }

    /// 次の 1 バイトを覗いて末尾かを判定する。読めたバイトは remainder に戻す。
    private func peekAtEnd() -> Bool {
        guard let peek = try? handle.read(upToCount: 1), !peek.isEmpty else { return true }
        remainder.insert(contentsOf: peek, at: remainder.startIndex)
        return false
    }
}
