import Foundation

/// ビューアが対応するファイル種別。拡張子から判定する。
enum FileType: Sendable {
    case mmd
    case markdown

    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "mmd", "mermaid":
            self = .mmd
        default:
            self = .markdown
        }
    }

    var jsValue: String {
        switch self {
        case .mmd: "mmd"
        case .markdown: "md"
        }
    }
}
