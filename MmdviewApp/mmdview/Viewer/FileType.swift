import Foundation

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
