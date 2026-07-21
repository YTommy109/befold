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
        abstract: "Mermaid/Markdown ビューア。ファイル/フォルダーを指定すると、それぞれ別ウィンドウで開きます。",
        usage: """
        befold [オプション] [ファイル/フォルダー...]
        befold <サブコマンド> [引数...]
        """,
        discussion: """
        オプション:
          --hidden-files          隠しファイルを表示する
          --no-hidden-files       隠しファイルを表示しない
          --sort <値>             並び順を指定する(folders-first|alphabetical)
          --line-numbers          行番号を表示する
          --no-line-numbers       行番号を表示しない
          --source                ソース表示モードで開く
          --preview               プレビュー表示モードで開く

        "check"/"bookmark" という名前のパスや、ハイフンで始まるパスを開く場合は \
        `--` 以降を常にパスとして扱う機能を使う(例: befold -- -notes.md)。

        `befold` コマンドは /Applications/befold.app 内の実行ファイルへの symlink です。\
        アプリを /Applications 以外へ移動した場合は、befold のアプリメニューから \
        「コマンドラインツールをインストール」を再度実行してください。
        """,
        subcommands: [OpenPathsCommand.self, BookmarkPassthroughCommand.self, CheckPassthroughCommand.self],
        defaultSubcommand: OpenPathsCommand.self
    )
}

/// `befold [オプション] [ファイル/フォルダー...]`。サブコマンド名(bookmark/check)が明示的に
/// 指定されなかった場合の既定の挙動(ファイル/フォルダーを開く)を担う。CLI 上は独立したサブコマンド名を
/// 持たず(defaultSubcommand)、`--help` にも表示しない。
struct OpenPathsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "open", shouldDisplay: false)

    @Argument(help: "開くファイル/フォルダーのパス(複数指定可)")
    var paths: [String] = []

    @Flag(name: .customLong("hidden-files"), help: "隠しファイルを表示する")
    var hiddenFilesOn = false
    @Flag(name: .customLong("no-hidden-files"), help: "隠しファイルを表示しない")
    var hiddenFilesOff = false

    @Option(name: .customLong("sort"), help: "並び順を指定する")
    var sortOrder: CLISortOrderOption?

    @Flag(name: .customLong("line-numbers"), help: "行番号を表示する")
    var lineNumbersOn = false
    @Flag(name: .customLong("no-line-numbers"), help: "行番号を表示しない")
    var lineNumbersOff = false

    @Flag(name: .customLong("source"), help: "ソース表示モードで開く")
    var sourceOn = false
    @Flag(name: .customLong("preview"), help: "プレビュー表示モードで開く")
    var sourceOff = false

    func validate() throws {
        if hiddenFilesOn, hiddenFilesOff {
            throw ValidationError("--hidden-files と --no-hidden-files は同時に指定できません")
        }
        if lineNumbersOn, lineNumbersOff {
            throw ValidationError("--line-numbers と --no-line-numbers は同時に指定できません")
        }
        if sourceOn, sourceOff {
            throw ValidationError("--source と --preview は同時に指定できません")
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
    static let configuration = CommandConfiguration(commandName: "bookmark")

    @Argument(parsing: .captureForPassthrough, help: "add <path> でファイル/フォルダーをブックマークに追加する")
    var arguments: [String] = []

    func run() throws {
        let result = MainActor.assumeIsolated { CLIBookmarkCommand.run(arguments) }
        CLICommandResultPrinter.printAndExit(result)
    }
}

/// `befold check <path>`。実際の引数検証・処理は既存の CLICheckCommand へ委譲する。
struct CheckPassthroughCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "check")

    @Argument(parsing: .captureForPassthrough, help: "指定したファイル/フォルダーが befold で開けるか確認する")
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
