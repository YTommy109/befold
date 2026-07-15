import Foundation

/// テキストを行単位のチャンクで逐次読み込む抽象(テストでの差し替え用)。
public protocol ChunkedTextReading: AnyObject {
    var isAtEnd: Bool { get }
    func readNextChunk() throws -> String
}

/// ファイルを行単位のチャンク(既定 1000 行 / 最大 4MB)で逐次読み込む。
/// チャンクセッションは UTF-8(ASCII 含む)専用とする。UTF-16 / UTF-32 のような
/// 行境界をバイト位置で確定できないエンコーディングに加え、Shift_JIS / EUC-JP 等の
/// レガシーエンコーディングも(強制分割時に文字境界を保証できないため)
/// 初期化時に `TextEncodingError.unsupportedForChunking` を投げ、
/// 呼び出し側の全量読み込みフォールバックに委ねる。
public final class LineChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000
    public static let maxChunkBytes = 4 * 1024 * 1024

    public private(set) var isAtEnd = false

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

        if let bom = TextEncoding.detectBOM(detectionProbe) {
            encoding = bom.encoding
            bomLength = bom.bomLength
        } else if let detected = TextEncoding.detectEncoding(detectionProbe) {
            encoding = detected
            bomLength = 0
        } else {
            encoding = .utf8
            bomLength = 0
        }

        // UTF-8 以外は強制分割時に文字境界を保証できないため、チャンク読み込みの
        // 対象外として全量読み込みへフォールバックさせる。
        guard encoding == .utf8 || encoding == .ascii else {
            try? handle.close()
            throw TextEncodingError.unsupportedForChunking
        }

        offset = UInt64(bomLength)
        try handle.seek(toOffset: offset)
    }

    deinit {
        try? handle.close()
    }

    public func readNextChunk() throws -> String {
        guard !isAtEnd else { return "" }

        var buffer = remainder
        remainder = Data()
        let bytesToRead = Self.maxChunkBytes - buffer.count
        if bytesToRead > 0, let fresh = try handle.read(upToCount: bytesToRead) {
            buffer.append(fresh)
        }

        if buffer.isEmpty {
            isAtEnd = true
            return ""
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
            chunkData = TextEncoding.trimIncompleteUTF8Tail(buffer)
            remainder = Data(buffer[chunkData.endIndex...])
            isAtEnd = false
        }

        guard let text = String(data: chunkData, encoding: encoding) else {
            throw TextEncodingError.decodeFailed
        }
        return text
    }

    /// 次の 1 バイトを覗いて末尾かを判定する。読めたバイトは remainder に戻す。
    private func peekAtEnd() -> Bool {
        guard let peek = try? handle.read(upToCount: 1), !peek.isEmpty else { return true }
        remainder.insert(contentsOf: peek, at: remainder.startIndex)
        return false
    }
}
