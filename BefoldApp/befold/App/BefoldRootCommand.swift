import ArgumentParser
import Foundation

/// サイドバー/フォルダー一覧の並び順。`SortOrder`(Viewer 層)に対応する CLI 向けの値。
enum CLISortOrderOption: String, Equatable, Codable, ExpressibleByArgument {
    case foldersFirst = "folders-first"
    case alphabetical
}

/// `-h`/`--help`・`--check`/`--bookmark` 以外の起動オプション。未指定の項目は既存の保存済み設定・既定値を維持する。
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

/// ファイルを開く際の表示オプション定義。BefoldRootCommand が単一の @OptionGroup として保持する
/// (root 以外にこれを共有する ParsableCommand は存在しないため、
/// サブコマンド名の前でフラグが黙殺される問題は構造的に起きない)。
struct OpenCLIOptions: ParsableArguments {
    @Flag(name: .customLong("hidden-files"), help: "Show hidden files in the sidebar.")
    var hiddenFilesOn = false
    @Flag(name: .customLong("no-hidden-files"), help: "Don't show hidden files in the sidebar.")
    var hiddenFilesOff = false

    @Option(name: .customLong("sort"), help: "Specify the sidebar sort order.")
    var sortOrder: CLISortOrderOption?

    @Flag(name: .customLong("line-numbers"), help: "Show line numbers in source view.")
    var lineNumbersOn = false
    @Flag(name: .customLong("no-line-numbers"), help: "Don't show line numbers in source view.")
    var lineNumbersOff = false

    @Flag(name: .customLong("source"), help: "Open in source view mode.")
    var sourceOn = false
    @Flag(name: .customLong("preview"), help: "Open in preview mode.")
    var sourceOff = false

    init() {}

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

    var cliOpenOptions: CLIOpenOptions {
        CLIOpenOptions(
            showHiddenFiles: hiddenFilesOn ? true : (hiddenFilesOff ? false : nil),
            sortOrder: sortOrder,
            showLineNumbers: lineNumbersOn ? true : (lineNumbersOff ? false : nil),
            sourceMode: sourceOn ? true : (sourceOff ? false : nil)
        )
    }
}

/// befold CLI のルートコマンド。`befold` シム経由で渡された argv を解析する。
/// swift-argument-parser に委譲することで、`--` ターミネータといった引数解析の
/// 落とし穴を自前実装せずに回避する。
///
/// `open`/`bookmark`/`check` は以前 `ParsableCommand` のサブコマンドだったが、
/// サブコマンド分割は「オプションがどのコマンドに属するか」が argv 上の位置に依存する
/// 問題を生む(open 専用フラグをサブコマンド名の前に置くと root が消費してしまい
/// 黙殺される)。トップレベル `--help` に open のオプションを表示する要求とは
/// 実装手段(`@OptionGroup` 共有)の上で両立しなかったため、サブコマンド分割自体を
/// 廃止し、単一コマンド + `--check`/`--bookmark` フラグに統合した。フラグは常に
/// トップレベルの実オプションであり、argv 上の位置に依存しない。
struct BefoldRootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "befold",
        abstract: "Mermaid/Markdown viewer.",
        usage: "befold [options] [file/folder...]",
        discussion: """
        Each path opens in its own window.
        To open a path starting with a hyphen, use `--` to treat everything after it \
        as paths (e.g. befold -- -notes.md).
        """,
        version: AppVersion.current
    )

    @Flag(name: .customLong("check"), help: "Check whether the given paths can be opened, instead of opening them.")
    var check = false

    @Flag(name: .customLong("bookmark"), help: "Bookmark the given paths, instead of opening them.")
    var bookmark = false

    @OptionGroup var openOptions: OpenCLIOptions

    @Argument(help: "Paths of files/folders to open (multiple allowed; also used as the target of --check/--bookmark).")
    var paths: [String] = []

    var options: CLIOpenOptions {
        openOptions.cliOpenOptions
    }

    func validate() throws {
        try openOptions.validate()
        if check || bookmark, paths.isEmpty {
            throw ValidationError("At least one path is required with --check/--bookmark.")
        }
    }

    func run() throws {
        guard check || bookmark else {
            AppDelegate.launch(withInitialPaths: paths, options: options)
            return
        }

        var anyFailed = false
        if check {
            for path in paths {
                let result = CLICheckCommand.run(path)
                CLICommandResultPrinter.print(result)
                if result.exitCode != 0 { anyFailed = true }
            }
        }
        if bookmark {
            for path in paths {
                let result = MainActor.assumeIsolated { CLIBookmarkCommand.run(path) }
                CLICommandResultPrinter.print(result)
                if result.exitCode != 0 { anyFailed = true }
            }
        }
        throw ExitCode(anyFailed ? 1 : 0)
    }
}

/// `CLICommandResult` を stdout/stderr へ出力する。終了コードの決定・プロセス終了は
/// 呼び出し側(`BefoldRootCommand.run()`)が担う(--check/--bookmark 併用時に
/// 複数件の結果をまとめて出力してから終了コードを決めるため)。
enum CLICommandResultPrinter {
    static func print(_ result: CLICommandResult) {
        if result.exitCode == 0 {
            Swift.print(result.message)
        } else {
            FileHandle.standardError.write(Data((result.message + "\n").utf8))
        }
    }
}
