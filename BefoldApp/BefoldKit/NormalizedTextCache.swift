import CryptoKit
import Foundation

/// NormalizedTextCache の初期化時に発生しうるエラー。
public enum NormalizedTextCacheError: Error, Sendable {
    /// ファイルサイズが maxFileSizeBytes を超えている。
    case fileTooLarge
}

/// ファイルの生データを改行コード正規化した文字列と行頭インデックスに変換して保持するキャッシュ。
/// エンコーディング判定・全文デコードは(正しさの保証のため)常に1回で行うが、
/// 改行正規化・行頭インデックス化は ensureNormalized で必要な範囲だけ増分的に行える。
/// normalizeFully: true(既定)の場合は従来どおり初期化時点で全量を正規化する。
public struct NormalizedTextCache: Sendable {
    public static let maxFileSizeBytes = 100 * 1024 * 1024

    /// 増分正規化1回あたりの処理バイト数(小さすぎる呼び出しの繰り返しを避けつつ、
    /// 先頭チャンク描画に必要な範囲だけを正規化できる程度の粒度にする)。
    static let normalizationWindowBytes = 2 * 1024 * 1024

    public let dataHash: Int

    /// 正規化済みバイト列(改行コードは LF に統一済み)。normalizeFully: false の場合、
    /// ensureNormalized で処理した範囲までしか含まない(ファイル全体とは限らない)。
    private var normalizedBytes: [UInt8]
    /// normalizedBytes 内の各行の先頭バイトオフセット。normalizedBytes と同様、
    /// 処理済み範囲までを保持する。
    private var lineStartOffsets: [Int]
    /// text/lineStartIndices/lineStartOffsets がファイル全体を反映しているかどうか。
    public private(set) var isFullyNormalized: Bool

    /// まだ正規化していないデコード済み残りテキスト。isFullyNormalized になった時点で
    /// 空文字列に置き換えてメモリを解放する。
    private var remainingSource: String
    /// remainingSource 内の現在の走査カーソル。追加正規化のたびに前方へだけ進む
    /// (先頭からの再走査を避けるため、常に直前のカーソルを起点に offsetBy で進める)。
    private var cursor: String.Index
    private var consumedUTF8Offset: Int
    private let sourceUTF8Count: Int
    /// 直前のウィンドウが裸の \r で終わった場合、次ウィンドウ先頭の \n を吸収するためのフラグ。
    private var pendingCarriageReturn = false

    public var text: String {
        String(decoding: normalizedBytes, as: UTF8.self)
    }

    public var lineStartIndices: [String.Index] {
        Self.stringIndices(forUTF8Offsets: lineStartOffsets, in: text)
    }

    public var lineCount: Int {
        lineStartOffsets.count
    }

    /// 生データをデコードし、正規化・行分割を行う。normalizeFully: false の場合、
    /// 呼び出し元が ensureNormalized で必要な範囲だけ追加正規化するまで、
    /// 正規化・行分割は行わない(先頭チャンクしか使わない読込でのピークメモリ・CPU を抑えるため)。
    public init(data: Data, normalizeFully: Bool = true) throws {
        if data.count > Self.maxFileSizeBytes {
            throw NormalizedTextCacheError.fileTooLarge
        }

        let hash = SHA256.hash(data: data)
        dataHash = hash.withUnsafeBytes { buffer in
            buffer.load(as: Int.self)
        }

        if data.isEmpty {
            normalizedBytes = []
            lineStartOffsets = []
            isFullyNormalized = true
            remainingSource = ""
            cursor = remainingSource.utf8.startIndex
            consumedUTF8Offset = 0
            sourceUTF8Count = 0
            return
        }

        guard let detected = TextEncoding.detectAndDecodeText(data),
              !detected.text.isEmpty || data.count == detected.bomLength
        else {
            throw TextEncodingError.decodeFailed
        }

        normalizedBytes = []
        lineStartOffsets = [0]
        isFullyNormalized = false
        remainingSource = detected.text
        cursor = remainingSource.utf8.startIndex
        consumedUTF8Offset = 0
        sourceUTF8Count = remainingSource.utf8.count

        if normalizeFully {
            ensureFullyNormalized()
        }
    }

    /// currentLine から少なくとも 1 チャンク分(行数 or バイト数の上限)を判定できるだけの
    /// 範囲を追加正規化する。minimumLineCount/minimumByteCount のどちらか一方でも満たすか、
    /// ファイル全体を正規化し終えた時点で停止する(呼び出し側は「先が判明した」ことだけを
    /// 保証されればよく、両方を満たす必要はない)。
    mutating func ensureNormalized(minimumLineCount: Int, minimumByteCount: Int) {
        while !isFullyNormalized, lineStartOffsets.count < minimumLineCount, normalizedBytes.count < minimumByteCount {
            growOneWindow()
        }
    }

    mutating func ensureFullyNormalized() {
        while !isFullyNormalized {
            growOneWindow()
        }
    }

    var normalizedByteCount: Int {
        normalizedBytes.count
    }

    func lineStart(_ line: Int) -> Int {
        lineStartOffsets[line]
    }

    func normalizedByte(at offset: Int) -> UInt8 {
        normalizedBytes[offset]
    }

    func chunkText(_ range: Range<Int>) -> String {
        String(decoding: normalizedBytes[range], as: UTF8.self)
    }

    /// UTF-8 継続バイト(0x80–0xBF)の途中を指している場合、そのマルチバイト文字の
    /// 先頭バイトまで後退させる。バイト数上限による強制分割はバイト単位の位置計算を
    /// 経由するため、文字境界を保証するにはこのスナップが必須。
    func snappedToCharacterBoundary(_ offset: Int, lowerBound: Int) -> Int {
        var offset = offset
        while offset > lowerBound, offset < normalizedBytes.count, (0x80 ... 0xBF).contains(normalizedBytes[offset]) {
            offset -= 1
        }
        return offset
    }

    /// remainingSource から最大 normalizationWindowBytes バイト分を1文字境界まで
    /// 切り出して正規化し、normalizedBytes/lineStartOffsets に追記する。
    private mutating func growOneWindow() {
        guard !isFullyNormalized else { return }

        let slice = remainingSource.utf8[cursor...]
        let window: [UInt8] = slice.withContiguousStorageIfAvailable { buffer -> [UInt8] in
            let limit = min(Self.normalizationWindowBytes, buffer.count)
            let boundary = Self.snappedBoundary(limit: limit, count: buffer.count) { buffer[$0] }
            return Array(buffer[0 ..< boundary])
        } ?? Self.copyWindowSlow(slice, limit: Self.normalizationWindowBytes)

        consume(window: window)

        cursor = remainingSource.utf8.index(cursor, offsetBy: window.count)
        consumedUTF8Offset += window.count

        if consumedUTF8Offset >= sourceUTF8Count {
            isFullyNormalized = true
            if lineStartOffsets.last == normalizedBytes.count {
                lineStartOffsets.removeLast()
            }
            remainingSource = ""
        }
    }

    /// 改行コード正規化(\r\n, \r → \n)と行頭バイトオフセットの収集を、与えられた
    /// window(すでに1文字境界までスナップ済み)に対して行う。pendingCarriageReturn で
    /// ウィンドウ境界をまたぐ \r\n を正しく1つの改行として扱う。
    private mutating func consume(window: [UInt8]) {
        normalizedBytes.reserveCapacity(normalizedBytes.count + window.count)
        var position = 0

        if pendingCarriageReturn {
            pendingCarriageReturn = false
            if !window.isEmpty, window[0] == 0x0A {
                position = 1
            }
        }

        while position < window.count {
            let currentByte = window[position]
            if currentByte == 0x0D {
                appendNewline()
                if position + 1 < window.count {
                    position += window[position + 1] == 0x0A ? 2 : 1
                } else {
                    pendingCarriageReturn = true
                    position += 1
                }
                continue
            }
            if currentByte == 0x0A {
                appendNewline()
                position += 1
                continue
            }
            normalizedBytes.append(currentByte)
            position += 1
        }
    }

    private mutating func appendNewline() {
        normalizedBytes.append(0x0A)
        lineStartOffsets.append(normalizedBytes.count)
    }

    /// 連続ストレージが取得できない(まれな)場合のフォールバック。1バイトずつ走査するが、
    /// 処理範囲は limit バイトに限られるため全文再走査にはならない。
    private static func copyWindowSlow(_ slice: Substring.UTF8View, limit: Int) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(limit)
        var iterator = slice.makeIterator()
        while result.count < limit, let byte = iterator.next() {
            result.append(byte)
        }
        guard let peeked = iterator.next() else {
            // スライスがちょうど limit で終わっている(=デコード済みテキストの末尾)ため
            // 境界調整は不要。
            return result
        }
        result.append(peeked)
        let boundary = snappedBoundary(limit: limit, count: result.count) { result[$0] }
        if boundary < result.count {
            result.removeLast(result.count - boundary)
        }
        return result
    }

    /// limit バイト目(byte(limit))が UTF-8 継続バイトなら、そのマルチバイト文字の
    /// 先頭バイトまで後退させた位置を返す。count は byte にアクセス可能な範囲の上限。
    private static func snappedBoundary(limit: Int, count: Int, byte: (Int) -> UInt8) -> Int {
        var boundary = limit
        while boundary > 0, boundary < count, (0x80 ... 0xBF).contains(byte(boundary)) {
            boundary -= 1
        }
        return boundary
    }

    /// UTF-8 バイトオフセット列を String.Index 列へ変換する。単調増加のオフセットを
    /// 前方へ1回だけ走査して変換するため、行ごとに index(after:) を呼び直すより高速。
    static func stringIndices(forUTF8Offsets offsets: [Int], in text: String) -> [String.Index] {
        guard !offsets.isEmpty else { return [] }
        var result: [String.Index] = []
        result.reserveCapacity(offsets.count)
        var cursor = text.utf8.startIndex
        var cursorOffset = 0
        for offset in offsets {
            cursor = text.utf8.index(cursor, offsetBy: offset - cursorOffset)
            cursorOffset = offset
            result.append(cursor)
        }
        return result
    }
}
