import ArgumentParser
@testable import befold_cli
import BefoldCLI
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// BefoldCLICommand の parseAsRoot 挙動を検証する。
/// open/bookmark/check のサブコマンド分割を廃止し、単一コマンド + --check/--bookmark
/// フラグへ統合したため、parseAsRoot は常に BefoldCLICommand 自身を返す。
@Suite
struct BefoldCLICommandTests {
    private func parseCommand(_ arguments: [String]) throws -> BefoldCLICommand {
        let command = try BefoldCLICommand.parseAsRoot(arguments)
        guard let root = command as? BefoldCLICommand else {
            Issue.record("expected BefoldCLICommand, got \(type(of: command))")
            throw ValidationError("unexpected command type")
        }
        return root
    }

    /// 本番の UserDefaults(`com.degino.befold`)と実 stdout/stderr に到達させずに実行する。
    /// 出力・ブックマーク内容を検証しないテストはこちらを使う。
    private func executeIsolated(_ command: BefoldCLICommand) throws {
        try command.execute(addBookmark: { _ in }, printResult: { _ in })
    }

    @Test("引数なしの場合は空のパス・既定オプションになる")
    func emptyArgumentsReturnsEmptyPaths() throws {
        let root = try parseCommand([])

        #expect(root.paths.isEmpty)
        #expect(root.options == CLIOpenOptions())
        #expect(!root.check)
        #expect(!root.bookmark)
    }

    @Test("ファイルパスのみの場合はそのままパスとして解釈する")
    func plainPathsAreParsedAsPaths() throws {
        let root = try parseCommand(["a.mmd", "b.md"])

        #expect(root.paths == ["a.mmd", "b.md"])
        #expect(root.options == CLIOpenOptions())
    }

    @Test("ヘルプ要求は run() がエラーを投げる", arguments: ["-h", "--help"])
    func helpFlagsThrowOnRun(flag: String) {
        #expect(throws: (any Error).self) {
            var command = try BefoldCLICommand.parseAsRoot([flag])
            try command.run()
        }
    }

    @Test("--check/--bookmark は値を取らないブールフラグとして解釈する")
    func checkAndBookmarkFlagsAreParsed() throws {
        let checkOnly = try parseCommand(["--check", "a.md"])
        #expect(checkOnly.check)
        #expect(!checkOnly.bookmark)
        #expect(checkOnly.paths == ["a.md"])

        let both = try parseCommand(["--check", "--bookmark", "a.md", "b.md"])
        #expect(both.check)
        #expect(both.bookmark)
        #expect(both.paths == ["a.md", "b.md"])
    }

    @Test("--check は複数パスを対象にし、1件でも失敗すれば終了コードが非0になる")
    func checkAggregatesMultiplePathsAndFailsIfAnyFails() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let existing = try tmp.file(named: "ok.md", contents: "# ok")
        let missing = tmp.url.appendingPathComponent("missing.md")

        let allOk = try parseCommand(["--check", existing.path])
        #expect(throws: ExitCode(0)) { try executeIsolated(allOk) }

        let oneMissing = try parseCommand(["--check", existing.path, missing.path])
        #expect(throws: ExitCode(1)) { try executeIsolated(oneMissing) }
    }

    @Test("--check と --bookmark を併用すると check→bookmark の順で両方実行され、失敗が集計される")
    @MainActor
    func checkAndBookmarkRunInOrderAndAggregateFailure() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let existing = try tmp.file(named: "ok.md", contents: "# ok")
        let missing = tmp.url.appendingPathComponent("missing.md")

        var bookmarked: [URL] = []
        var messages: [String] = []
        let both = try parseCommand(["--check", "--bookmark", existing.path, missing.path])

        #expect(throws: ExitCode(1)) {
            try both.execute(
                addBookmark: { bookmarked.append($0) },
                printResult: { messages.append($0.message) }
            )
        }

        // 全パスの check を終えてから bookmark に移る順序を、出力の並びで確認する。
        #expect(messages.count == 4)
        #expect(messages[0].contains("Can open:"))
        #expect(messages[1].contains("No such path: \(missing.path)"))
        #expect(messages[2].contains("Bookmarked: \(existing.path)"))
        #expect(messages[3].contains("No such path: \(missing.path)"))
        // 存在しないパスは fileExists ガードで弾かれ、実在する側だけが登録される。
        #expect(bookmarked.map(\.path) == [existing.path])
    }

    @Test("旧サブコマンド名と同名のパスはサブコマンドと解釈されず、そのまま open 対象になる")
    func formerSubcommandNamesAreTreatedAsPlainPaths() throws {
        let root = try parseCommand(["--hidden-files", "check", "/tmp/a"])

        #expect(root.paths == ["check", "/tmp/a"])
        #expect(root.options.showHiddenFiles == true)
        #expect(!root.check)
    }

    @Test("`--` 以降はハイフンで始まるパスでもオプションと解釈されない")
    func dashDashEscapesHyphenPrefixedPaths() throws {
        let root = try parseCommand(["--hidden-files", "--", "-notes.md"])

        #expect(root.paths == ["-notes.md"])
        #expect(root.options == CLIOpenOptions(showHiddenFiles: true))
    }

    @Test(
        "表示オプションのフラグを対応する CLIOpenOptions に解釈する",
        arguments: [
            (["--hidden-files"], CLIOpenOptions(showHiddenFiles: true)),
            (["--no-hidden-files"], CLIOpenOptions(showHiddenFiles: false)),
            (["--line-numbers"], CLIOpenOptions(showLineNumbers: true)),
            (["--no-line-numbers"], CLIOpenOptions(showLineNumbers: false)),
            (["--source"], CLIOpenOptions(sourceMode: true)),
            (["--preview"], CLIOpenOptions(sourceMode: false)),
            (["--sort", "folders-first"], CLIOpenOptions(sortOrder: .foldersFirst)),
            (["--sort", "alphabetical"], CLIOpenOptions(sortOrder: .alphabetical)),
        ]
    )
    func displayOptionsAreParsed(arguments: [String], expected: CLIOpenOptions) throws {
        #expect(try parseCommand(arguments).options == expected)
    }

    @Test(
        "不正な引数はエラーになる",
        arguments: [
            ["--no-such-option"],
            ["--check"],
            ["--bookmark"],
            ["--hidden-files", "--no-hidden-files"],
            ["--sort"],
            ["--sort", "reverse"],
        ]
    )
    func invalidArgumentsThrow(arguments: [String]) {
        #expect(throws: (any Error).self) { try BefoldCLICommand.parseAsRoot(arguments) }
    }

    @Test("オプションとファイルパスは混在指定できる")
    func optionsAndPathsCanBeMixed() throws {
        let root = try parseCommand(["--hidden-files", "a.md", "--source", "b.md"])

        #expect(root.paths == ["a.md", "b.md"])
        #expect(root.options == CLIOpenOptions(showHiddenFiles: true, sourceMode: true))
    }

    @Test("configuration.version は AppVersion.current と一致する(単一の情報源)")
    func versionMatchesAppVersionConstant() {
        #expect(!AppVersion.current.isEmpty)
        #expect(BefoldCLICommand.configuration.version == AppVersion.current)
    }

    /// project.yml の MARKETING_VERSION(言語をまたぐ定数)を実ファイルから読み取り、
    /// AppVersion.current とのドリフトを検知する(ViewerBridgeTests のソース突き合わせの流儀)。
    @Test("project.yml の MARKETING_VERSION が AppVersion.current と一致する")
    func projectYmlMarketingVersionMatchesAppVersionConstant() throws {
        let projectYmlURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldCLITests/
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

    @Test("help文言は英語で統一されている")
    func helpTextIsEnglishOnly() {
        #expect(BefoldCLICommand.configuration.abstract == "Mermaid/Markdown viewer.")
    }

    @Test(
        "トップレベル --help に全オプションが表示される",
        arguments: [
            "--check", "--bookmark", "--hidden-files",
            "--sort", "--line-numbers", "--source", "--preview",
        ]
    )
    func allOptionsAppearInTopLevelHelp(option: String) {
        #expect(BefoldCLICommand.helpMessage().contains(option))
    }

    @Test(
        "--help の --sort 項目で指定可能な値が確認できる",
        arguments: ["folders-first", "alphabetical"]
    )
    func sortHelpListsAvailableValues(value: String) {
        #expect(BefoldCLICommand.helpMessage().contains(value))
    }

    @Test("不正な --sort 値のエラーメッセージに候補が含まれる")
    func invalidSortValueErrorListsCandidates() {
        do {
            _ = try BefoldCLICommand.parseAsRoot(["--sort", "reverse"])
            Issue.record("expected parse to throw for an invalid --sort value")
        } catch {
            let message = BefoldCLICommand.fullMessage(for: error)
            #expect(message.contains("folders-first"))
            #expect(message.contains("alphabetical"))
        }
    }

    @Test(
        "discussion に -- エスケープと複数パスのウィンドウ挙動が記載されている",
        arguments: ["treat everything after it as paths", "its own window"]
    )
    func discussionDescribesUsageNotes(note: String) {
        #expect(BefoldCLICommand.configuration.discussion.contains(note))
    }
}

/// CLI が出すファイル種別の拒否理由メッセージを検証する。
@Suite
struct RejectReasonCLIMessageTests {
    @Test(
        "RejectReason.cliMessage はロケールに依存しない英語固定メッセージを返す",
        arguments: [
            (RejectReason.unsupportedFormat, "This file format is not supported for preview."),
            (RejectReason.fileTooLarge, "This file is too large to display."),
        ]
    )
    func cliMessageIsEnglish(reason: RejectReason, expected: String) {
        #expect(reason.cliMessage == expected)
    }
}
