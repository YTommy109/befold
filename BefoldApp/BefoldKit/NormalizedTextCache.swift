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

        guard let detected = TextEncoding.detectEncoding(data) else {
            throw TextEncodingError.decodeFailed
        }
        let payload = data.dropFirst(detected.bomLength)
        guard let decoded = String(data: payload, encoding: detected.encoding),
              !decoded.isEmpty || payload.isEmpty
        else {
            throw TextEncodingError.decodeFailed
        }

        text = Self.normalizeLineEndings(decoded)
        lineStartIndices = Self.buildLineStartIndices(text)
    }

    static func normalizeLineEndings(_ str: String) -> String {
        str.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func buildLineStartIndices(_ text: String) -> [String.Index] {
        guard !text.isEmpty else { return [] }
        var indices: [String.Index] = [text.startIndex]
        var idx = text.startIndex
        while idx < text.endIndex {
            if text[idx] == "\n" {
                let next = text.index(after: idx)
                if next < text.endIndex {
                    indices.append(next)
                }
            }
            idx = text.index(after: idx)
        }
        return indices
    }
}
