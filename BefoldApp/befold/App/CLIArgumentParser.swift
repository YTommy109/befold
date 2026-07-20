import Foundation

/// CLI 起動時に指定できるサブコマンドの仕様。実体のディスパッチは各サブコマンド実装側が持つ。
struct CLISubcommandSpec: Equatable {
    let name: String
    let summary: String
}

/// サイドバー/フォルダー一覧の並び順。`SortOrder`(Viewer 層)に対応する CLI 向けの値。
enum CLISortOrderOption: String, Equatable, Codable {
    case foldersFirst = "folders-first"
    case alphabetical
}

/// `-h`/`--help`・サブコマンド以外の起動オプション。未指定の項目は既存の保存済み設定・既定値を維持する。
struct CLIOpenOptions: Equatable, Codable {
    var showHiddenFiles: Bool?
    var sortOrder: CLISortOrderOption?
    var showLineNumbers: Bool?
    var sourceMode: Bool?
}

/// argv を解析した結果のコマンド種別。
enum CLICommand: Equatable {
    /// 指定されたファイル/フォルダーパス群(0件を含む)と表示オプション。
    case openPaths([String], options: CLIOpenOptions)
    /// `-h` / `--help`。
    case help
    /// 登録済みサブコマンド名と、その後続引数。
    case subcommand(name: String, arguments: [String])
}

struct CLIParseError: Error, Equatable {
    let message: String
}

/// CLI 引数パーサー基盤。`befold` シム経由で渡された argv を解析する。
enum CLIArgumentParser {
    /// 登録済みサブコマンド一覧。
    static let subcommands: [CLISubcommandSpec] = [
        CLISubcommandSpec(name: "bookmark", summary: "ファイル/フォルダーをブックマークに追加する(bookmark add <path>)"),
        CLISubcommandSpec(name: "check", summary: "befold で開けるファイルかどうかを確認する(check <path>)"),
    ]

    static var usageText: String {
        var lines = [
            "使い方: befold [オプション] [ファイル/フォルダー...]",
            "       befold <サブコマンド> [引数...]",
            "",
            "ファイル/フォルダーを指定すると、それぞれ別ウィンドウで開きます。",
            "",
            "オプション:",
            "  -h, --help              このヘルプを表示する",
            "  --hidden-files          隠しファイルを表示する",
            "  --no-hidden-files       隠しファイルを表示しない",
            "  --sort <値>             並び順を指定する(folders-first|alphabetical)",
            "  --line-numbers          行番号を表示する",
            "  --no-line-numbers       行番号を表示しない",
            "  --source                ソース表示モードで開く",
            "  --preview               プレビュー表示モードで開く",
        ]
        if !subcommands.isEmpty {
            lines.append("")
            lines.append("サブコマンド:")
            lines.append(contentsOf: subcommands.map { "  \($0.name)\t\($0.summary)" })
        }
        return lines.joined(separator: "\n")
    }

    /// `arguments` は `CommandLine.arguments` の先頭(実行ファイルパス)を除いたものを渡す。
    static func parse(
        _ arguments: [String],
        subcommands: [CLISubcommandSpec] = CLIArgumentParser.subcommands
    ) -> Result<CLICommand, CLIParseError> {
        guard let first = arguments.first else {
            return .success(.openPaths([], options: CLIOpenOptions()))
        }

        if let spec = subcommands.first(where: { $0.name == first }) {
            return .success(.subcommand(name: spec.name, arguments: Array(arguments.dropFirst())))
        }

        return parseOpenPaths(arguments)
    }

    /// 値を伴わない on/off フラグの一覧。`apply` で対応する `CLIOpenOptions` のプロパティへ反映する。
    private enum BooleanFlag: CaseIterable {
        case hiddenFiles, noHiddenFiles, lineNumbers, noLineNumbers, source, preview

        var rawValue: String {
            switch self {
            case .hiddenFiles: "--hidden-files"
            case .noHiddenFiles: "--no-hidden-files"
            case .lineNumbers: "--line-numbers"
            case .noLineNumbers: "--no-line-numbers"
            case .source: "--source"
            case .preview: "--preview"
            }
        }

        func apply(to options: inout CLIOpenOptions) {
            switch self {
            case .hiddenFiles: options.showHiddenFiles = true
            case .noHiddenFiles: options.showHiddenFiles = false
            case .lineNumbers: options.showLineNumbers = true
            case .noLineNumbers: options.showLineNumbers = false
            case .source: options.sourceMode = true
            case .preview: options.sourceMode = false
            }
        }
    }

    private static func parseOpenPaths(_ arguments: [String]) -> Result<CLICommand, CLIParseError> {
        var paths: [String] = []
        var options = CLIOpenOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "-h" || argument == "--help" {
                return .success(.help)
            }
            if let flag = BooleanFlag.allCases.first(where: { $0.rawValue == argument }) {
                flag.apply(to: &options)
                continue
            }
            if argument == "--sort" {
                switch parseSortOrder(&iterator) {
                case let .success(sortOrder): options.sortOrder = sortOrder
                case let .failure(error): return .failure(error)
                }
                continue
            }
            if argument.hasPrefix("-") {
                return .failure(CLIParseError(message: "不明なオプションです: \(argument)\n\n\(usageText)"))
            }
            paths.append(argument)
        }
        return .success(.openPaths(paths, options: options))
    }

    private static func parseSortOrder(
        _ iterator: inout IndexingIterator<[String]>
    ) -> Result<CLISortOrderOption, CLIParseError> {
        guard let rawValue = iterator.next() else {
            return .failure(CLIParseError(message: "--sort には値が必要です\n\n\(usageText)"))
        }
        guard let sortOrder = CLISortOrderOption(rawValue: rawValue) else {
            return .failure(CLIParseError(message: "不明な --sort の値です: \(rawValue)\n\n\(usageText)"))
        }
        return .success(sortOrder)
    }
}
