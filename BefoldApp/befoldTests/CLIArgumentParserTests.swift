@testable import befold
import Testing

@Suite
struct CLIArgumentParserTests {
    @Test("引数なしの場合は空の openPaths を返す(既存の GUI 起動と互換)")
    func emptyArgumentsReturnsEmptyOpenPaths() throws {
        let result = CLIArgumentParser.parse([])

        #expect(try result.get() == .openPaths([], options: CLIOpenOptions()))
    }

    @Test("ファイルパスのみの場合は openPaths として解釈する")
    func plainPathsAreParsedAsOpenPaths() throws {
        let result = CLIArgumentParser.parse(["a.mmd", "b.md"])

        #expect(try result.get() == .openPaths(["a.mmd", "b.md"], options: CLIOpenOptions()))
    }

    @Test("-h / --help は help コマンドとして解釈する")
    func helpFlagsReturnHelp() throws {
        #expect(try CLIArgumentParser.parse(["-h"]).get() == .help)
        #expect(try CLIArgumentParser.parse(["--help"]).get() == .help)
    }

    @Test("--help はパスと混在していてもどこにあっても help を返す")
    func helpFlagAmongPathsReturnsHelp() throws {
        #expect(try CLIArgumentParser.parse(["a.md", "--help"]).get() == .help)
    }

    @Test("未知のオプションはエラーになり usage を含む")
    func unknownOptionReturnsErrorWithUsage() {
        let result = CLIArgumentParser.parse(["--no-such-option"])

        switch result {
        case .success:
            Issue.record("expected failure")
        case let .failure(error):
            #expect(error.message.contains("--no-such-option"))
            #expect(error.message.contains(CLIArgumentParser.usageText))
        }
    }

    @Test("登録済みサブコマンドは subcommand として解釈し、残りの引数を渡す")
    func registeredSubcommandIsParsed() throws {
        let spec = CLISubcommandSpec(name: "greet", summary: "テスト用")
        let result = CLIArgumentParser.parse(["greet", "world"], subcommands: [spec])

        #expect(try result.get() == .subcommand(name: "greet", arguments: ["world"]))
    }

    @Test("未登録の語はサブコマンドではなくファイルパスとして扱う")
    func unregisteredWordIsTreatedAsPath() throws {
        let result = CLIArgumentParser.parse(["greet"], subcommands: [])

        #expect(try result.get() == .openPaths(["greet"], options: CLIOpenOptions()))
    }

    @Test("usage には既定のオプション説明が含まれる")
    func usageTextContainsHelpOption() {
        #expect(CLIArgumentParser.usageText.contains("--help"))
    }

    @Test("bookmark は既定で登録済みサブコマンドとして解釈される(TASK-73.4)")
    func bookmarkIsRegisteredByDefault() throws {
        let result = CLIArgumentParser.parse(["bookmark", "add", "/tmp/a.mmd"])

        #expect(try result.get() == .subcommand(name: "bookmark", arguments: ["add", "/tmp/a.mmd"]))
    }

    @Test("usage には bookmark サブコマンドの説明が含まれる")
    func usageTextContainsBookmarkSubcommand() {
        #expect(CLIArgumentParser.usageText.contains("bookmark"))
    }

    @Test("check は既定で登録済みサブコマンドとして解釈される(TASK-73.5)")
    func checkIsRegisteredByDefault() throws {
        let result = CLIArgumentParser.parse(["check", "/tmp/a.mmd"])

        #expect(try result.get() == .subcommand(name: "check", arguments: ["/tmp/a.mmd"]))
    }

    @Test("usage には check サブコマンドの説明が含まれる")
    func usageTextContainsCheckSubcommand() {
        #expect(CLIArgumentParser.usageText.contains("check"))
    }

    @Test("--hidden-files / --no-hidden-files を解釈する")
    func hiddenFilesOptionIsParsed() throws {
        #expect(try CLIArgumentParser.parse(["--hidden-files"]).get() == .openPaths(
            [], options: CLIOpenOptions(showHiddenFiles: true)
        ))
        #expect(try CLIArgumentParser.parse(["--no-hidden-files"]).get() == .openPaths(
            [], options: CLIOpenOptions(showHiddenFiles: false)
        ))
    }

    @Test("--line-numbers / --no-line-numbers を解釈する")
    func lineNumbersOptionIsParsed() throws {
        #expect(try CLIArgumentParser.parse(["--line-numbers"]).get() == .openPaths(
            [], options: CLIOpenOptions(showLineNumbers: true)
        ))
        #expect(try CLIArgumentParser.parse(["--no-line-numbers"]).get() == .openPaths(
            [], options: CLIOpenOptions(showLineNumbers: false)
        ))
    }

    @Test("--source / --preview を解釈する")
    func sourcePreviewOptionIsParsed() throws {
        #expect(try CLIArgumentParser.parse(["--source"]).get() == .openPaths(
            [], options: CLIOpenOptions(sourceMode: true)
        ))
        #expect(try CLIArgumentParser.parse(["--preview"]).get() == .openPaths(
            [], options: CLIOpenOptions(sourceMode: false)
        ))
    }

    @Test("--sort は値を伴い folders-first / alphabetical を解釈する")
    func sortOptionIsParsed() throws {
        #expect(try CLIArgumentParser.parse(["--sort", "folders-first"]).get() == .openPaths(
            [], options: CLIOpenOptions(sortOrder: .foldersFirst)
        ))
        #expect(try CLIArgumentParser.parse(["--sort", "alphabetical"]).get() == .openPaths(
            [], options: CLIOpenOptions(sortOrder: .alphabetical)
        ))
    }

    @Test("--sort に値がない場合はエラーになる")
    func sortOptionWithoutValueReturnsError() {
        let result = CLIArgumentParser.parse(["--sort"])

        switch result {
        case .success:
            Issue.record("expected failure")
        case let .failure(error):
            #expect(error.message.contains("--sort"))
        }
    }

    @Test("--sort に不正な値を渡すとエラーになる")
    func sortOptionWithInvalidValueReturnsError() {
        let result = CLIArgumentParser.parse(["--sort", "reverse"])

        switch result {
        case .success:
            Issue.record("expected failure")
        case let .failure(error):
            #expect(error.message.contains("reverse"))
        }
    }

    @Test("オプションとファイルパスは混在指定できる")
    func optionsAndPathsCanBeMixed() throws {
        let result = CLIArgumentParser.parse(["--hidden-files", "a.md", "--source", "b.md"])

        #expect(try result.get() == .openPaths(
            ["a.md", "b.md"], options: CLIOpenOptions(showHiddenFiles: true, sourceMode: true)
        ))
    }
}
