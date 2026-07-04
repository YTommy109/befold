import Foundation

/// ビューアが対応するファイル種別。拡張子から判定する。
/// 対応拡張子の一覧はここが単一情報源(オープンパネルの許可種別もここから解決する)。
enum FileType: Sendable {
    case mmd
    case markdown

    /// mermaid ダイアグラムとして扱う拡張子。
    static let mermaidExtensions = ["mmd", "mermaid"]
    /// markdown として扱う拡張子。
    static let markdownExtensions = ["md", "markdown"]
    /// アプリが対応する全拡張子。
    static let allExtensions = mermaidExtensions + markdownExtensions

    init(url: URL) {
        self = Self.mermaidExtensions.contains(url.pathExtension.lowercased()) ? .mmd : .markdown
    }

    var jsValue: String {
        switch self {
        case .mmd: "mmd"
        case .markdown: "md"
        }
    }
}
