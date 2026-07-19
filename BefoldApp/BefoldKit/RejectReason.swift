import Foundation

/// ファイルを表示できない理由。
public enum RejectReason: Error, Sendable, Equatable {
    /// バイナリなど非対応形式。
    case unsupportedFormat
    /// ファイルサイズが上限を超えている。
    case fileTooLarge

    /// ユーザー向けの表示文言。BefoldKit のリソースバンドルから取得するため、
    /// アプリ本体だけでなく QuickLook 拡張(appex)からも利用できる。
    public var localizedMessage: String {
        switch self {
        case .unsupportedFormat:
            String(localized: "viewer.unsupported.format", bundle: .befoldKitResources)
        case .fileTooLarge:
            String(localized: "viewer.unsupported.tooLarge", bundle: .befoldKitResources)
        }
    }
}
