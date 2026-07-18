import Foundation

/// ビューアが対応するファイル種別。拡張子から判定する。
public enum FileType: Sendable, Equatable {
    case mmd
    case markdown
    case svg
    case html
    case csv(delimiter: String)
    case image(mimeType: String)
    case pdf
    case code(language: String)

    /// mermaid ダイアグラムとして扱う拡張子。
    public static let mermaidExtensions = ["mmd", "mermaid"]
    /// markdown として扱う拡張子。
    public static let markdownExtensions = ["md", "markdown"]
    /// SVG として扱う拡張子。
    public static let svgExtensions = ["svg"]
    /// HTML として扱う拡張子。
    public static let htmlExtensions = ["html", "htm"]
    /// CSV として扱う拡張子。
    public static let csvExtensions = ["csv"]
    /// TSV として扱う拡張子。
    public static let tsvExtensions = ["tsv"]
    /// コードとして扱う拡張子 → highlight.js の言語名。
    /// 同梱 highlight.min.js が対応する言語のみを載せる
    /// (整合性は viewer.test.js が同梱ビルドの言語リストと突き合わせて検証する)。
    public static let codeExtensionLanguages: [String: String] = [
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
        "xml": "xml", "plist": "xml",
        "vb": "vbnet",
    ]
    /// コードとして扱う拡張子。
    public static let codeExtensions = [String](codeExtensionLanguages.keys)
    /// 画像拡張子 → MIME タイプ。
    public static let imageExtensionMimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "bmp": "image/bmp",
        "ico": "image/x-icon",
    ]
    /// PDF として扱う拡張子。
    public static let pdfExtensions = ["pdf"]
    /// 未知の拡張子に対するフォールバック種別。
    public static let plaintextFallback: FileType = .code(language: "plaintext")
    /// 拡張子 → FileType の単一対応表。`init(url:)` と `allExtensions` の唯一の情報源。
    private static let typeByExtension: [String: FileType] = {
        var map: [String: FileType] = [:]
        for ext in mermaidExtensions {
            map[ext] = .mmd
        }
        for ext in markdownExtensions {
            map[ext] = .markdown
        }
        for ext in svgExtensions {
            map[ext] = .svg
        }
        for ext in htmlExtensions {
            map[ext] = .html
        }
        for ext in csvExtensions {
            map[ext] = .csv(delimiter: ",")
        }
        for ext in tsvExtensions {
            map[ext] = .csv(delimiter: "\t")
        }
        for (ext, mime) in imageExtensionMimeTypes {
            map[ext] = .image(mimeType: mime)
        }
        for ext in pdfExtensions {
            map[ext] = .pdf
        }
        for (ext, lang) in codeExtensionLanguages {
            map[ext] = .code(language: lang)
        }
        return map
    }()

    /// 対応する全拡張子。
    public static let allExtensions: Set<String> = Set(typeByExtension.keys)

    /// 拡張子が `allExtensions` に含まれる既知の拡張子かどうかを判定する。
    /// `allExtensions` に無い拡張子でも `init(url:)` は plaintext としてフォールバックするため、
    /// この判定は「開けるか」ではなく「拡張子を既知としてハンドリングできるか」を表す。
    public static func isSupported(_ url: URL) -> Bool {
        allExtensions.contains(url.pathExtension.lowercased())
    }

    public init(url: URL) {
        self = Self.typeByExtension[url.pathExtension.lowercased()] ?? Self.plaintextFallback
    }

    public var jsValue: String {
        switch self {
        case .mmd: "mmd"
        case .markdown: "md"
        case .svg: "svg"
        case .html: "html"
        case .csv: "csv"
        case .image: "image"
        case .pdf: "pdf"
        case .code: "code"
        }
    }

    /// .code の highlight.js 言語名。他の種別は nil。
    public var codeLanguage: String? {
        if case let .code(language) = self { return language }
        return nil
    }

    /// .csv の区切り文字。他の種別は nil。
    public var csvDelimiter: String? {
        if case let .csv(delimiter) = self { return delimiter }
        return nil
    }

    /// .image の MIME タイプ。他の種別は nil。
    public var imageMimeType: String? {
        if case let .image(mimeType) = self { return mimeType }
        return nil
    }

    /// JS の render(content, type, lang) に渡す第 3 引数(lang)。取らない種別は nil。
    /// .code は highlight.js の言語名、.csv は区切り文字、.image は MIME タイプ。
    /// いずれも FileType の対応表由来の固定文字列のみで、ユーザー入力は混入しない。
    public var renderLangArgument: String? {
        codeLanguage ?? csvDelimiter ?? imageMimeType
    }

    /// バイナリファイルとして読み込むべき種別かどうか。
    public var isBinaryContent: Bool {
        switch self {
        case .image, .pdf: true
        case .mmd, .markdown, .svg, .html, .csv, .code: false
        }
    }

    /// レンダリング表示が可能な種別かどうか。false ならソース表示のみ。
    public var isRenderable: Bool {
        switch self {
        case .mmd, .markdown, .svg, .html, .csv, .image, .pdf: true
        case .code: false
        }
    }

    /// ソース表示(レンダリングとの切り替え)に対応する種別かどうか。
    /// バイナリ(画像・PDF)にはテキストソースがないため対象外。
    public var supportsSourceMode: Bool {
        isRenderable && !isBinaryContent
    }

    /// 行指向の形式かどうか。チャンク読み込みの対象判定に使う。
    /// CSV/TSV とコード(プレーンテキスト含む)が該当する。
    /// Markdown/Mermaid/HTML/SVG は途中切断で描画が壊れるため対象外。
    public var isLineOriented: Bool {
        switch self {
        case .csv, .code: true
        case .mmd, .markdown, .svg, .html, .image, .pdf: false
        }
    }
}
