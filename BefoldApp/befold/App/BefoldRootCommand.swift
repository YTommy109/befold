import ArgumentParser
import Foundation

/// サイドバー/フォルダー一覧の並び順。`SortOrder`(Viewer 層)に対応する CLI 向けの値。
enum CLISortOrderOption: String, Equatable, Codable, ExpressibleByArgument {
    case foldersFirst = "folders-first"
    case alphabetical
}

/// `-h`/`--help`・サブコマンド以外の起動オプション。未指定の項目は既存の保存済み設定・既定値を維持する。
struct CLIOpenOptions: Equatable, Codable {
    var showHiddenFiles: Bool?
    var sortOrder: CLISortOrderOption?
    var showLineNumbers: Bool?
    var sourceMode: Bool?

    /// Viewer 層の `SortOrder` へ変換したもの。未指定時は既定の `.foldersFirst`。
    var viewerSortOrder: SortOrder {
        sortOrder == .alphabetical ? .alphabetical : .foldersFirst
    }
}

/// befold CLI のルートコマンド。`befold` シム経由で渡された argv を解析する。
/// swift-argument-parser に委譲することで、`--` ターミネータやサブコマンド名の衝突といった
/// 引数解析の落とし穴(TASK-73.9/73.10 参照)を自前実装せずに回避する。
/// ルート自身は positional 引数を持たない(サブコマンドの配列引数と競合し、
/// "bookmark"/"check" がサブコマンドとしてではなくパスとして飲み込まれてしまうため)。
/// ファイル/フォルダーを開く既定の挙動は `OpenPathsCommand`(非表示の defaultSubcommand)が担う。
struct BefoldRootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "befold",
        abstract: "Mermaid/Markdown viewer.",
        usage: """
        befold [options] [file/folder...]
        befold <subcommand> [args...]
        """,
        discussion: """
        Opening a file/folder without a subcommand is the same as `befold open` \
        (the default action). See `befold open --help` for its options.
        """,
        version: AppVersion.current,
        subcommands: [OpenPathsCommand.self, BookmarkPassthroughCommand.self, CheckPassthroughCommand.self],
        defaultSubcommand: OpenPathsCommand.self
    )
}

/// `befold [オプション] [ファイル/フォルダー...]`。サブコマンド名(bookmark/check)が明示的に
/// 指定されなかった場合の既定の挙動(ファイル/フォルダーを開く)を担う。CLI 上は独立したサブコマンド名を
/// 持たず(defaultSubcommand)、`--help` にも表示しない。
struct OpenPathsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open a file/folder (the default action when no subcommand is given).",
        discussion: """
        To open a path literally named "check"/"bookmark", or one starting with a hyphen, \
        use `--` to treat everything after it as paths (e.g. befold -- -notes.md).
        """
    )

    @Argument(help: "Paths of files/folders to open (multiple allowed).")
    var paths: [String] = []

    @Flag(name: .customLong("hidden-files"), help: "Show hidden files.")
    var hiddenFilesOn = false
    @Flag(name: .customLong("no-hidden-files"), help: "Don't show hidden files.")
    var hiddenFilesOff = false

    @Option(name: .customLong("sort"), help: "Specify the sort order.")
    var sortOrder: CLISortOrderOption?

    @Flag(name: .customLong("line-numbers"), help: "Show line numbers.")
    var lineNumbersOn = false
    @Flag(name: .customLong("no-line-numbers"), help: "Don't show line numbers.")
    var lineNumbersOff = false

    @Flag(name: .customLong("source"), help: "Open in source view mode.")
    var sourceOn = false
    @Flag(name: .customLong("preview"), help: "Open in preview mode.")
    var sourceOff = false

    func validate() throws {
        if hiddenFilesOn, hiddenFilesOff {
            throw ValidationError("--hidden-files and --no-hidden-files cannot be specified together.")
        }
        if lineNumbersOn, lineNumbersOff {
            throw ValidationError("--line-numbers and --no-line-numbers cannot be specified together.")
        }
        if sourceOn, sourceOff {
            throw ValidationError("--source and --preview cannot be specified together.")
        }
    }

    var options: CLIOpenOptions {
        CLIOpenOptions(
            showHiddenFiles: hiddenFilesOn ? true : (hiddenFilesOff ? false : nil),
            sortOrder: sortOrder,
            showLineNumbers: lineNumbersOn ? true : (lineNumbersOff ? false : nil),
            sourceMode: sourceOn ? true : (sourceOff ? false : nil)
        )
    }

    func run() throws {
        AppDelegate.launch(withInitialPaths: paths, options: options)
    }
}

/// `befold bookmark [add <path>]`。実際の引数検証・処理は既存の CLIBookmarkCommand へ委譲する
/// (add 以外の語や引数不足のエラーメッセージ・終了コードは CLIBookmarkCommand が持つ)。
struct BookmarkPassthroughCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "bookmark", abstract: "Manage bookmarks.")

    @Argument(parsing: .captureForPassthrough, help: "Bookmark a file/folder with `add <path>`.")
    var arguments: [String] = []

    func run() throws {
        let result = MainActor.assumeIsolated { CLIBookmarkCommand.run(arguments) }
        CLICommandResultPrinter.printAndExit(result)
    }
}

/// `befold check <path>`。実際の引数検証・処理は既存の CLICheckCommand へ委譲する。
struct CheckPassthroughCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: "Check whether befold can open a file/folder."
    )

    @Argument(parsing: .captureForPassthrough, help: "Check whether befold can open the given file/folder.")
    var arguments: [String] = []

    func run() throws {
        let result = CLICheckCommand.run(arguments)
        CLICommandResultPrinter.printAndExit(result)
    }
}

/// `CLICommandResult` を stdout/stderr へ出力し、対応する終了コードでプロセスを終了する。
enum CLICommandResultPrinter {
    static func printAndExit(_ result: CLICommandResult) -> Never {
        if result.exitCode == 0 {
            print(result.message)
        } else {
            FileHandle.standardError.write(Data((result.message + "\n").utf8))
        }
        exit(result.exitCode)
    }
}
