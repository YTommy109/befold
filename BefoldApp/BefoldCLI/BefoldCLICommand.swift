import ArgumentParser
import BefoldKit
import Foundation

/// `befold` コマンドの本体。
///
/// **実行ファイル(`befold-cli`)ではなくこの framework に置く。** 実行ファイルターゲットの
/// 中身は `@testable import` できても Xcode のテストホストにできない(plain tool は
/// TEST_HOST として受け付けられない)ため、ここに無いと `befoldCLITests` が
/// `xcodebuild test` の経路に載らない(TASK-456)。実行ファイル側は
/// `BefoldCLIEntryPoint.run()` を呼ぶだけの薄い入口に保つこと。
struct BefoldCLICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "befold",
        abstract: "Mermaid/Markdown viewer.",
        usage: "befold [options] [file/folder...]",
        discussion: """
        Each path opens in its own window.
        To open a path starting with a hyphen, use `--` to treat everything after it \
        as paths (e.g. befold -- -notes.md).
        """,
        version: AppVersion.currentWithBuild
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
        if check || bookmark, paths.isEmpty {
            throw ValidationError("At least one path is required with --check/--bookmark.")
        }
        // 表示オプションは開く文書に対する指定なので、適用先が無い呼び出しでは黙って
        // 捨てずにここで弾く(--check/--bookmark はウィンドウを開かないため適用先が無い)。
        guard options.requiresPaths else { return }
        if paths.isEmpty {
            throw ValidationError(Self.displayOptionsRequirePathMessage)
        }
        if check || bookmark {
            throw ValidationError(
                "Display options (--source/--preview, --line-numbers/--no-line-numbers, "
                    + "--sidebar/--no-sidebar, --sort) cannot be combined with --check/--bookmark, "
                    + "which don't open a window."
            )
        }
    }

    /// パス無しで表示オプションだけを渡したときの案内。対象フラグを列挙して、
    /// アプリ全体設定の `--hidden-files` は対象外であることまで伝える。
    static let displayOptionsRequirePathMessage = """
    Display options (--source/--preview, --line-numbers/--no-line-numbers, \
    --sidebar/--no-sidebar, --sort) apply to the file being opened, so at least one path is required. \
    Use --hidden-files/--no-hidden-files to change the app-wide setting without opening a file.
    """

    @MainActor
    func run() async throws {
        try await execute(
            addBookmark: { url in
                await CLIBookmarkRouter.add(url, addLocally: { BefoldCLICommand.bookmarkStore.add($0) })
            },
            printResult: CLICommandResultPrinter.print
        )
    }

    /// `run()` の実体。ブックマークの追加先と結果の出力先を注入できるようにしている。
    /// 既定の追加先は起動中インスタンスがあれば GUI プロセス、無ければ GUI と共有する
    /// UserDefaults(`com.degino.befold`)= 利用者の実データ(CLIBookmarkRouter 参照)、
    /// 既定の出力先は実プロセスの stdout/stderr のため、テストからは差し替えて使う。
    @MainActor
    func execute(
        addBookmark: @MainActor (URL) async -> Bool,
        printResult: (CLICommandResult) -> Void
    ) async throws {
        if !check, !bookmark {
            await CLIAppLauncher.launch(paths: paths, options: options)
        }

        var anyFailed = false
        if check {
            // 判定は GUI と同じ ViewerLoadPipeline へ委譲する(CLICheckCommand 参照)。
            // I/O とデコードは nonisolated な pipeline 側で行われ、メインスレッドは塞がない。
            let failed = await runForEachPath(printResult: printResult) { await CLICheckCommand.run($0) }
            anyFailed = anyFailed || failed
        }
        if bookmark {
            let failed = await runForEachPath(printResult: printResult) {
                await CLIBookmarkCommand.run($0, addBookmark: addBookmark)
            }
            anyFailed = anyFailed || failed
        }
        throw ExitCode(anyFailed ? 1 : 0)
    }

    /// 全パスへ `command` を順に適用し、結果を都度出力しながら「1 つでも失敗したか」を返す。
    /// 失敗したパスがあっても打ち切らず、最後まで実行してから終了コードへ集約する
    /// (`--check` と `--bookmark` で結果集約の約束を 1 箇所に固定するための共通経路)。
    @MainActor
    private func runForEachPath(
        printResult: (CLICommandResult) -> Void,
        command: @MainActor (String) async -> CLICommandResult
    ) async -> Bool {
        var anyFailed = false
        for path in paths {
            let result = await command(path)
            printResult(result)
            if result.exitCode != 0 { anyFailed = true }
        }
        return anyFailed
    }

    /// `--bookmark` 実行時、GUI アプリを起動せずに直接 GUI と同じ UserDefaults 領域へ
    /// ブックマークを追加する(BookmarkStore は GUI・CLI 共通の実装元、BefoldKit 参照)。
    /// befold-cli はバンドルを持たない実行ファイルのため、GUI アプリのバンドル ID を
    /// suiteName に明示して同じ永続化領域を指す。
    @MainActor
    private static let bookmarkStore = BookmarkStore(
        defaults: UserDefaults(suiteName: AppBundle.identifier) ?? .standard
    )
}

/// 実行ファイルから CLI を起動するための唯一の公開入口。
///
/// コマンド本体(`BefoldCLICommand`)を public にせず、この 1 点だけを外へ出す。
/// ArgumentParser の宣言(`@Flag` / `@Option` / `@Argument`)まで public 化すると、
/// framework の公開 API がコマンドラインの内部構造そのものになってしまう。
public enum BefoldCLIEntryPoint {
    /// 引数を解釈してコマンドを実行する。戻らない(ArgumentParser が exit する)。
    public static func run() async {
        await BefoldCLICommand.main()
    }
}
