import ArgumentParser
@testable import befold
import Foundation
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

    @Test("configuration.version は AppVersion.current と一致する(単一の情報源)")
    func versionMatchesAppVersionConstant() {
        #expect(!AppVersion.current.isEmpty)
        #expect(BefoldRootCommand.configuration.version == AppVersion.current)
    }

    /// project.yml の MARKETING_VERSION(言語をまたぐ定数)を実ファイルから読み取り、
    /// AppVersion.current とのドリフトを検知する(ViewerBridgeTests のソース突き合わせの流儀)。
    @Test("project.yml の MARKETING_VERSION が AppVersion.current と一致する")
    func projectYmlMarketingVersionMatchesAppVersionConstant() throws {
        let projectYmlURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests/
            .deletingLastPathComponent() // BefoldApp/
            .appendingPathComponent("project.yml")
        let projectYml = try String(contentsOf: projectYmlURL, encoding: .utf8)

        let marketingVersionLine = try #require(
            projectYml.components(separatedBy: .newlines).first { $0.contains("MARKETING_VERSION:") }
        )
        let marketingVersion = marketingVersionLine
            .components(separatedBy: "MARKETING_VERSION:")[1]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        #expect(marketingVersion == AppVersion.current)
    }

    @Test("help文言は英語で統一されている(TASK-94.3)")
    func helpTextIsEnglishOnly() {
        #expect(BefoldRootCommand.configuration.abstract == "Mermaid/Markdown viewer.")
        #expect(OpenPathsCommand.configuration.abstract.hasPrefix("Open a file/folder"))
    }

    @Test("bookmark/check サブコマンドには一目でわかる abstract がある(TASK-94.4)")
    func bookmarkAndCheckHaveAbstracts() {
        #expect(BookmarkPassthroughCommand.configuration.abstract == "Manage bookmarks.")
        #expect(CheckPassthroughCommand.configuration.abstract == "Check whether befold can open a file/folder.")
    }

    @Test("open はデフォルト挙動として --help のサブコマンド一覧に表示される(TASK-94.4)")
    func openSubcommandIsDisplayedInHelp() {
        #expect(OpenPathsCommand.configuration.shouldDisplay)
        #expect(OpenPathsCommand.configuration.abstract.contains("default"))
    }

    @Test("root の discussion は簡潔になり、open のオプション参照先を案内する(TASK-94.4)")
    func rootDiscussionIsConciseAndPointsToOpenHelp() {
        let discussion = BefoldRootCommand.configuration.discussion

        #expect(discussion.contains("befold open --help"))
        #expect(!discussion.contains("symlink"))
        #expect(discussion.count < 200)
    }

    @Test("open の discussion に -- エスケープの案内がある(TASK-94.4)")
    func openDiscussionHasEscapingNote() {
        let discussion = OpenPathsCommand.configuration.discussion

        #expect(discussion.contains("--"))
    }

    @Test("サブコマンド名を省略しても open 相当のオプションが引き続き正しく解釈される(トップレベル共有後の回帰確認)")
    func openOptionsStillParseWithoutSubcommandName() throws {
        let open = try parseRoot(["--hidden-files", "a.md", "--sort", "alphabetical"])

        #expect(open.paths == ["a.md"])
        #expect(open.options == CLIOpenOptions(showHiddenFiles: true, sortOrder: .alphabetical))
    }
}
