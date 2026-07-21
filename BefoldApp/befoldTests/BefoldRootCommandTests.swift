import ArgumentParser
@testable import befold
import Testing

/// BefoldRootCommand(swift-argument-parser への移行、TASK-76)の parseAsRoot 挙動を検証する。
@Suite
struct BefoldRootCommandTests {
    private func parseRoot(_ arguments: [String]) throws -> OpenPathsCommand {
        let command = try BefoldRootCommand.parseAsRoot(arguments)
        guard let open = command as? OpenPathsCommand else {
            Issue.record("expected OpenPathsCommand, got \(type(of: command))")
            throw ValidationError("unexpected command type")
        }
        return open
    }

    @Test("引数なしの場合は空のパス・既定オプションになる(defaultSubcommand)")
    func emptyArgumentsReturnsEmptyPaths() throws {
        let open = try parseRoot([])

        #expect(open.paths.isEmpty)
        #expect(open.options == CLIOpenOptions())
    }

    @Test("ファイルパスのみの場合はそのままパスとして解釈する")
    func plainPathsAreParsedAsPaths() throws {
        let open = try parseRoot(["a.mmd", "b.md"])

        #expect(open.paths == ["a.mmd", "b.md"])
        #expect(open.options == CLIOpenOptions())
    }

    @Test("-h / --help はヘルプ要求として run() がエラーを投げる")
    func helpFlagsThrowOnRun() {
        #expect(throws: (any Error).self) {
            var command = try BefoldRootCommand.parseAsRoot(["-h"])
            try command.run()
        }
        #expect(throws: (any Error).self) {
            var command = try BefoldRootCommand.parseAsRoot(["--help"])
            try command.run()
        }
    }

    @Test("未知のオプションはエラーになる")
    func unknownOptionThrows() {
        #expect(throws: (any Error).self) { try BefoldRootCommand.parseAsRoot(["--no-such-option"]) }
    }

    @Test("登録済みサブコマンド bookmark/check は subcommand として解釈する(TASK-73.4/73.5)")
    func registeredSubcommandsAreParsed() throws {
        let bookmark = try BefoldRootCommand.parseAsRoot(["bookmark", "add", "/tmp/a.mmd"])
        #expect((bookmark as? BookmarkPassthroughCommand)?.arguments == ["add", "/tmp/a.mmd"])

        let check = try BefoldRootCommand.parseAsRoot(["check", "/tmp/a.mmd"])
        #expect((check as? CheckPassthroughCommand)?.arguments == ["/tmp/a.mmd"])
    }

    @Test("`--` 以降は check/bookmark という名前のパスでもサブコマンドと解釈されない(TASK-73.9)")
    func dashDashEscapesSubcommandLikePathNames() throws {
        let open = try parseRoot(["--", "check"])

        #expect(open.paths == ["check"])
    }

    @Test("`--` 以降はハイフンで始まるパスでもオプションと解釈されない(TASK-73.10)")
    func dashDashEscapesHyphenPrefixedPaths() throws {
        let open = try parseRoot(["--hidden-files", "--", "-notes.md"])

        #expect(open.paths == ["-notes.md"])
        #expect(open.options == CLIOpenOptions(showHiddenFiles: true))
    }

    @Test("--hidden-files / --no-hidden-files を解釈する")
    func hiddenFilesOptionIsParsed() throws {
        #expect(try parseRoot(["--hidden-files"]).options == CLIOpenOptions(showHiddenFiles: true))
        #expect(try parseRoot(["--no-hidden-files"]).options == CLIOpenOptions(showHiddenFiles: false))
    }

    @Test("--hidden-files と --no-hidden-files を同時に指定するとエラーになる")
    func conflictingHiddenFilesFlagsThrow() {
        #expect(throws: (any Error).self) {
            try BefoldRootCommand.parseAsRoot(["--hidden-files", "--no-hidden-files"])
        }
    }

    @Test("--line-numbers / --no-line-numbers を解釈する")
    func lineNumbersOptionIsParsed() throws {
        #expect(try parseRoot(["--line-numbers"]).options == CLIOpenOptions(showLineNumbers: true))
        #expect(try parseRoot(["--no-line-numbers"]).options == CLIOpenOptions(showLineNumbers: false))
    }

    @Test("--source / --preview を解釈する")
    func sourcePreviewOptionIsParsed() throws {
        #expect(try parseRoot(["--source"]).options == CLIOpenOptions(sourceMode: true))
        #expect(try parseRoot(["--preview"]).options == CLIOpenOptions(sourceMode: false))
    }

    @Test("--sort は folders-first / alphabetical を解釈する")
    func sortOptionIsParsed() throws {
        #expect(try parseRoot(["--sort", "folders-first"]).options == CLIOpenOptions(sortOrder: .foldersFirst))
        #expect(try parseRoot(["--sort", "alphabetical"]).options == CLIOpenOptions(sortOrder: .alphabetical))
    }

    @Test("--sort に値がない場合はエラーになる")
    func sortOptionWithoutValueThrows() {
        #expect(throws: (any Error).self) { try BefoldRootCommand.parseAsRoot(["--sort"]) }
    }

    @Test("--sort に不正な値を渡すとエラーになる")
    func sortOptionWithInvalidValueThrows() {
        #expect(throws: (any Error).self) { try BefoldRootCommand.parseAsRoot(["--sort", "reverse"]) }
    }

    @Test("オプションとファイルパスは混在指定できる")
    func optionsAndPathsCanBeMixed() throws {
        let open = try parseRoot(["--hidden-files", "a.md", "--source", "b.md"])

        #expect(open.paths == ["a.md", "b.md"])
        #expect(open.options == CLIOpenOptions(showHiddenFiles: true, sourceMode: true))
    }
}
