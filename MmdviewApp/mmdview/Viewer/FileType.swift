import Foundation

/// ビューアが対応するファイル種別。拡張子から判定する。
enum FileType: Sendable, Equatable {
    case mmd
    case markdown
    case code(language: String)

    /// mermaid ダイアグラムとして扱う拡張子。
    static let mermaidExtensions = ["mmd", "mermaid"]
    /// markdown として扱う拡張子。
    static let markdownExtensions = ["md", "markdown"]
    /// コードとして扱う拡張子 → highlight.js の言語名。
    /// 同梱 highlight.min.js が対応する言語のみを載せる
    /// (整合性は viewer.test.js が同梱ビルドの言語リストと突き合わせて検証する)。
    static let codeExtensionLanguages: [String: String] = [
        "swift": "swift", "py": "python", "go": "go", "rs": "rust",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "java": "java", "kt": "kotlin", "kts": "kotlin",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp",
        "cs": "csharp", "m": "objectivec", "mm": "objectivec",
        "rb": "ruby", "php": "php", "pl": "perl", "pm": "perl",
        "lua": "lua", "r": "r", "sql": "sql",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "graphql": "graphql", "gql": "graphql",
        "css": "css", "scss": "scss", "less": "less",
        "ini": "ini", "toml": "ini",
        "diff": "diff", "patch": "diff",
        "mk": "makefile",
        "json": "json", "jsonc": "json",
        "yaml": "yaml", "yml": "yaml",
        "xml": "xml", "plist": "xml", "svg": "xml",
        "vb": "vbnet",
    ]
    /// コードとして扱う拡張子。
    static let codeExtensions = [String](codeExtensionLanguages.keys)

    init(url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.mermaidExtensions.contains(ext) {
            self = .mmd
        } else if let language = Self.codeExtensionLanguages[ext] {
            self = .code(language: language)
        } else if Self.markdownExtensions.contains(ext) {
            self = .markdown
        } else {
            self = .code(language: "plaintext")
        }
    }

    var jsValue: String {
        switch self {
        case .mmd: "mmd"
        case .markdown: "md"
        case .code: "code"
        }
    }

    /// .code の highlight.js 言語名。他の種別は nil。
    var codeLanguage: String? {
        if case let .code(language) = self { return language }
        return nil
    }
}
