import ArgumentParser
@testable import befold
import BefoldKit
import Foundation
import Testing

/// BefoldRootCommand の parseAsRoot 挙動を検証する。
/// open/bookmark/check のサブコマンド分割を廃止し、単一コマンド + --check/--bookmark
/// フラグへ統合したため、parseAsRoot は常に BefoldRootCommand 自身を返す。
@Suite
struct BefoldRootCommandTests {
    private func parseRoot(_ arguments: [String]) throws -> BefoldRootCommand {
        let command = try BefoldRootCommand.parseAsRoot(arguments)
        guard let root = command as? BefoldRootCommand else {
            Issue.record("expected BefoldRootCommand, got \(type(of: command))")
            throw ValidationError("unexpected command type")
        }
        return root
    }

    @Test("引数なしの場合は空のパス・既定オプションになる")
    func emptyArgumentsReturnsEmptyPaths() throws {
        let root = try parseRoot([])

        #expect(root.paths.isEmpty)
        #expect(root.options == CLIOpenOptions())
        #expect(!root.check)
        #expect(!root.bookmark)
    }

    @Test("ファイルパスのみの場合はそのままパスとして解釈する")
    func plainPathsAreParsedAsPaths() throws {
        let root = try parseRoot(["a.mmd", "b.md"])

        #expect(root.paths == ["a.mmd", "b.md"])
        #expect(root.options == CLIOpenOptions())
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

    @Test("--check/--bookmark は値を取らないブールフラグとして解釈する(TASK-104)")
    func checkAndBookmarkFlagsAreParsed() throws {
        let checkOnly = try parseRoot(["--check", "a.md"])
        #expect(checkOnly.check)
        #expect(!checkOnly.bookmark)
        #expect(checkOnly.paths == ["a.md"])

        let both = try parseRoot(["--check", "--bookmark", "a.md", "b.md"])
        #expect(both.check)
        #expect(both.bookmark)
        #expect(both.paths == ["a.md", "b.md"])
    }

    @Test("--check/--bookmark 指定時に paths が空だとエラーになる(TASK-104)")
    func checkOrBookmarkWithoutPathsThrows() {
        #expect(throws: (any Error).self) { try BefoldRootCommand.parseAsRoot(["--check"]) }
        #expect(throws: (any Error).self) { try BefoldRootCommand.parseAsRoot(["--bookmark"]) }
    }

    @Test("--check は複数パスを対象にし、1件でも失敗すれば終了コードが非0になる(TASK-104)")
    func checkAggregatesMultiplePathsAndFailsIfAnyFails() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let existing = try tmp.file(named: "ok.md", contents: "# ok")

        let allOk = try parseRoot(["--check", existing.path])
        #expect(throws: ExitCode(0)) { try allOk.run() }

        let oneMissing = try parseRoot(["--check", existing.path, "/tmp/does-not-exist.md"])
        #expect(throws: ExitCode(1)) { try oneMissing.run() }
    }

    @Test("--check と --bookmark を併用すると check→bookmark の順で両方実行され、失敗が集計される(TASK-104)")
    @MainActor
    func checkAndBookmarkRunInOrderAndAggregateFailure() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let existing = try tmp.file(named: "ok.md", contents: "# ok")

        // bookmark 対象を存在しないパスにすることで、CLIBookmarkCommand.run の
        // fileExists ガードで早期リターンさせ、実 UserDefaults への書き込みを避けつつ
        // check→bookmark の両方が実行されることと、失敗集計を検証する。
        let both = try parseRoot(["--check", "--bookmark", existing.path, "/tmp/does-not-exist-for-bookmark.md"])
        #expect(throws: ExitCode(1)) { try both.run() }
    }

    @Test("旧サブコマンド名と同名のパスはサブコマンドと解釈されず、そのまま open 対象になる(TASK-104)")
    func formerSubcommandNamesAreTreatedAsPlainPaths() throws {
        let root = try parseRoot(["--hidden-files", "check", "/tmp/a"])

        #expect(root.paths == ["check", "/tmp/a"])
        #expect(root.options.showHiddenFiles == true)
        #expect(!root.check)
    }

    @Test("`--` 以降はハイフンで始まるパスでもオプションと解釈されない(TASK-73.10)")
    func dashDashEscapesHyphenPrefixedPaths() throws {
        let root = try parseRoot(["--hidden-files", "--", "-notes.md"])

        #expect(root.paths == ["-notes.md"])
        #expect(root.options == CLIOpenOptions(showHiddenFiles: true))
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
        let root = try parseRoot(["--hidden-files", "a.md", "--source", "b.md"])

        #expect(root.paths == ["a.md", "b.md"])
        #expect(root.options == CLIOpenOptions(showHiddenFiles: true, sourceMode: true))
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
    }

    @Test("トップレベル --help に全オプションが表示される(TASK-104)")
    func allOptionsAppearInTopLevelHelp() {
        let help = BefoldRootCommand.helpMessage()

        #expect(help.contains("--check"))
        #expect(help.contains("--bookmark"))
        #expect(help.contains("--hidden-files"))
        #expect(help.contains("--sort"))
        #expect(help.contains("--line-numbers"))
        #expect(help.contains("--source"))
        #expect(help.contains("--preview"))
    }

    @Test("open の discussion に -- エスケープの案内がある")
    func discussionHasEscapingNote() {
        let discussion = BefoldRootCommand.configuration.discussion

        #expect(discussion.contains("treat everything after it as paths"))
    }

    @Test("discussion に複数パスのウィンドウ挙動が記載されている(TASK-100)")
    func discussionDescribesMultipleWindowBehavior() {
        let discussion = BefoldRootCommand.configuration.discussion

        #expect(discussion.contains("its own window"))
    }

    @Test("RejectReason.cliMessage はロケールに依存しない英語固定メッセージを返す(TASK-98)")
    func rejectReasonCliMessageIsEnglish() {
        #expect(RejectReason.unsupportedFormat.cliMessage == "This file format is not supported for preview.")
        #expect(RejectReason.fileTooLarge.cliMessage == "This file is too large to display.")
    }
}
