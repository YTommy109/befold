import Foundation

/// ファイルを表示できない理由。
public enum RejectReason: Error, Sendable, Equatable {
    /// バイナリなど非対応形式。
    case unsupportedFormat
    /// ファイルサイズが上限を超えている。
    case fileTooLarge
}
