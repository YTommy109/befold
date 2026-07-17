import CryptoKit
import Foundation

public enum NormalizedTextCacheError: Error, Sendable {
    case fileTooLarge
}

public struct NormalizedTextCache: Sendable {
    public static let maxFileSizeBytes = 100 * 1024 * 1024

    public let text: String
    public let lineStartIndices: [String.Index]
    public let dataHash: Int

    public var lineCount: Int {
        lineStartIndices.count
    }

    public init(data: Data) throws {
        if data.count > Self.maxFileSizeBytes {
            throw NormalizedTextCacheError.fileTooLarge
        }

        let hash = SHA256.hash(data: data)
        dataHash = hash.withUnsafeBytes { buffer in
            buffer.load(as: Int.self)
        }

        if data.isEmpty {
            text = ""
            lineStartIndices = []
            return
        }

        guard let detected = TextEncoding.detectAndDecodeText(data),
              !detected.text.isEmpty || data.count == detected.bomLength
        else {
            throw TextEncodingError.decodeFailed
        }
        let decoded = detected.text

        let (normalizedUTF8, lineStartOffsets) = Self.normalizeAndFindLineStarts(decoded)
        let normalized = String(decoding: normalizedUTF8, as: UTF8.self)
        text = normalized
        lineStartIndices = Self.stringIndices(forUTF8Offsets: lineStartOffsets, in: normalized)
    }

    /// 改行コード正規化(\r\n, \r → \n)と行頭バイトオフセットの収集を1パスで行う。
    /// デコード済み文字列自身の UTF-8 表現を走査するため、元ファイルのエンコーディング
    /// (SJIS/UTF-16/UTF-32 等、1文字あたりのバイト幅が異なるもの)に関わらず安全に扱える。
    /// Character 単位(書記素クラスタ境界計算)の走査を避けることで大幅に高速化している。
    static func normalizeAndFindLineStarts(_ text: String) -> (normalizedUTF8: [UInt8], lineStartOffsets: [Int]) {
        var normalizedBytes: [UInt8] = []
        var lineStartOffsets = [0]

        func appendNewline() {
            normalizedBytes.append(0x0A)
            lineStartOffsets.append(normalizedBytes.count)
        }

        let handledContiguously: Void? = text.utf8.withContiguousStorageIfAvailable { sourceBuffer in
            normalizedBytes.reserveCapacity(sourceBuffer.count)
            var position = 0
            let byteCount = sourceBuffer.count
            while position < byteCount {
                let currentByte = sourceBuffer[position]
                if currentByte == 0x0D {
                    appendNewline()
                    let isCRLF = position + 1 < byteCount && sourceBuffer[position + 1] == 0x0A
                    position += isCRLF ? 2 : 1
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

        if handledContiguously == nil {
            var previousWasCarriageReturn = false
            for currentByte in text.utf8 {
                if currentByte == 0x0D {
                    appendNewline()
                    previousWasCarriageReturn = true
                    continue
                }
                if currentByte == 0x0A {
                    if previousWasCarriageReturn {
                        previousWasCarriageReturn = false
                        continue
                    }
                    appendNewline()
                    continue
                }
                previousWasCarriageReturn = false
                normalizedBytes.append(currentByte)
            }
        }

        if lineStartOffsets.last == normalizedBytes.count {
            lineStartOffsets.removeLast()
        }
        return (normalizedBytes, lineStartOffsets)
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
