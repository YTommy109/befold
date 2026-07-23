import ArgumentParser
import BefoldCLI
import Foundation

@main
struct BefoldCLICommand: ParsableCommand {
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
            CLIAppLauncher.launch(paths: paths, options: options)
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
                let result = MainActor.assumeIsolated {
                    CLIBookmarkCommand.run(
                        path,
                        addBookmark: { CLIBookmarkDefaults.add($0) }
                    )
                }
                CLICommandResultPrinter.print(result)
                if result.exitCode != 0 { anyFailed = true }
            }
        }
        throw ExitCode(anyFailed ? 1 : 0)
    }
}

enum CLIBookmarkDefaults {
    private static let defaultsKey = "BookmarkedPaths"
    private static let suiteName = "com.degino.befold"

    @MainActor
    static func add(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let path = url.standardizedFileURL.path
        var paths = defaults.stringArray(forKey: defaultsKey) ?? []
        guard !paths.contains(path) else { return }
        paths.append(path)
        defaults.set(paths, forKey: defaultsKey)
    }
}
