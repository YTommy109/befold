import Foundation

/// テキストを行単位のチャンクで逐次読み込む抽象(テストでの差し替え用)。
public protocol ChunkedTextReading: AnyObject {
    var isAtEnd: Bool { get }
    func readNextChunk() throws -> String
}

/// ファイルを行単位のチャンク(既定 1000 行 / 最大 4MB)で逐次読み込む。
/// UTF-16 / UTF-32 など行境界をバイト位置で確定できないエンコーディングは
/// 初期化時に `TextEncodingError.unsupportedForChunking` を投げる。
public final class LineChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000
    public static let maxChunkBytes = 4 * 1024 * 1024

    public private(set) var isAtEnd = false

    private let handle: FileHandle
    private let encoding: String.Encoding
    private let bomLength: Int
    private var offset: UInt64
    private var remainder = Data()

    public init(url: URL) throws {
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

        if let bom = TextEncoding.detectBOM(probe) {
            encoding = bom.encoding
            bomLength = bom.bomLength
        } else if let detected = TextEncoding.detectEncoding(probe) {
            encoding = detected
            bomLength = 0
        } else {
            encoding = .utf8
            bomLength = 0
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

        var lineCount = 0
        var splitIndex: Data.Index?
        for index in buffer.indices where buffer[index] == 0x0A {
            lineCount += 1
            if lineCount >= Self.linesPerChunk {
                splitIndex = buffer.index(after: index)
                break
            }
        }

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
            chunkData = trimToCharacterBoundary(buffer)
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

    /// UTF-8 の場合、末尾がマルチバイト文字の途中で切れないよう先頭バイトまで戻す。
    private func trimToCharacterBoundary(_ data: Data) -> Data {
        guard encoding == .utf8 else { return data }
        var end = data.endIndex
        while end > data.startIndex {
            let byte = data[data.index(before: end)]
            if byte & 0x80 == 0 { break }
            if byte & 0xC0 != 0x80 {
                end = data.index(before: end)
                break
            }
            end = data.index(before: end)
        }
        return data[data.startIndex ..< end]
    }
}
