import Foundation

/// 管理パネルへのドロップ 1 回分の結果。追加した分と、弾いた分(理由付き)。
/// ビューはこれを 1 行の文言にまとめる(モーダルは出さない。ドロップは連続で起きる)。
struct BookmarkDropOutcome: Equatable, Sendable {
    enum Rejection: Equatable, Sendable {
        /// 存在しない(ドロップ時点の stat で見えない)。
        case missing
        /// 通常ファイルで、対応形式の拡張子でない。
        case unsupported
    }

    struct Rejected: Equatable, Sendable {
        let url: URL
        let reason: Rejection
    }

    var added: [URL] = []
    var rejected: [Rejected] = []

    /// 弾いた分があるときだけの 1 行。「n 件を追加できませんでした: 名前 (理由), …」。
    /// 全件受け入れなら nil(何も出さない)。
    var feedback: String? {
        guard !rejected.isEmpty else { return nil }
        let head = String(localized: "bookmarks.manager.drop.rejected \(rejected.count)", bundle: .l10n)
        let details = rejected.map { "\($0.url.lastPathComponent) (\($0.reason.localizedReason))" }
        return head + ": " + details.joined(separator: ", ")
    }
}

extension BookmarkDropOutcome.Rejection {
    var localizedReason: String {
        switch self {
        case .missing: String(localized: "bookmarks.manager.drop.missing", bundle: .l10n)
        case .unsupported: String(localized: "bookmarks.manager.drop.unsupported", bundle: .l10n)
        }
    }
}
