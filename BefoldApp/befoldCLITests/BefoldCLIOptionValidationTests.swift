import ArgumentParser
@testable import befold_cli
import BefoldCLI
import Foundation
import Testing

/// 表示オプションが「対象の文書」を必要とすることを、パース段階で強制できているかを検証する。
///
/// 表示オプションはどれも開く文書に対する指定なので、対象が無い呼び出し
/// (パス無し、または開かない --check/--bookmark)では黙って捨てるのではなくエラーにする。
/// 例外は `--hidden-files`/`--no-hidden-files` だけで、これはアプリ全体設定のため対象を要さない。
@Suite
struct BefoldCLIOptionValidationTests {
    /// パスを要する表示フラグの実引数。表の 1 行が 1 フラグに対応する。
    private nonisolated static let documentScopedFlags: [[String]] = [
        ["--source"], ["--preview"],
        ["--line-numbers"], ["--no-line-numbers"],
        ["--sidebar"], ["--no-sidebar"],
        ["--sort", "alphabetical"],
    ]

    /// 対象を要さないアプリ全体設定のフラグ。
    private nonisolated static let globalFlags: [[String]] = [["--hidden-files"], ["--no-hidden-files"]]

    @Test("パス無しで表示フラグを渡すとエラーになる", arguments: documentScopedFlags)
    func documentScopedFlagsRequirePaths(_ arguments: [String]) {
        #expect(throws: (any Error).self) {
            _ = try BefoldCLICommand.parseAsRoot(arguments)
        }
    }

    @Test("パス無しでもアプリ全体設定のフラグは受け付ける", arguments: globalFlags)
    func globalFlagsDoNotRequirePaths(_ arguments: [String]) throws {
        let command = try #require(try BefoldCLICommand.parseAsRoot(arguments) as? BefoldCLICommand)

        #expect(command.paths.isEmpty)
        #expect(command.options.showHiddenFiles != nil)
    }

    @Test("パスを付ければ表示フラグは受け付ける", arguments: documentScopedFlags)
    func documentScopedFlagsAreAcceptedWithPaths(_ arguments: [String]) throws {
        let command = try #require(
            try BefoldCLICommand.parseAsRoot(arguments + ["a.md"]) as? BefoldCLICommand
        )

        #expect(command.paths == ["a.md"])
    }

    /// --check/--bookmark はウィンドウを開かないため、表示フラグを渡しても適用先が無い
    /// (現状は黙って無視される)。パス無しと同じ「対象が無い」ケースとして弾く。
    @Test("開かない --check/--bookmark と表示フラグの併用はエラーになる", arguments: ["--check", "--bookmark"])
    func nonOpeningModesRejectDocumentScopedFlags(_ mode: String) {
        #expect(throws: (any Error).self) {
            _ = try BefoldCLICommand.parseAsRoot([mode, "--source", "a.md"])
        }
    }

    @Test("--check/--bookmark はアプリ全体設定のフラグとは併用できる")
    func nonOpeningModesAcceptGlobalFlags() throws {
        let command = try #require(
            try BefoldCLICommand.parseAsRoot(["--check", "--hidden-files", "a.md"]) as? BefoldCLICommand
        )

        #expect(command.check)
    }

    /// requiresPaths の判定は `options != CLIOpenOptions()` では書けない
    /// (--hidden-files 単独を誤って弾く)。フィールドごとの判定であることを固定する。
    @Test("requiresPaths はアプリ全体設定を除く指定の有無で決まる")
    func requiresPathsCoversEveryDocumentScopedField() {
        #expect(!CLIOpenOptions().requiresPaths)
        #expect(!CLIOpenOptions(showHiddenFiles: true).requiresPaths)
        #expect(CLIOpenOptions(sortOrder: .alphabetical).requiresPaths)
        #expect(CLIOpenOptions(showLineNumbers: false).requiresPaths)
        #expect(CLIOpenOptions(sourceMode: false).requiresPaths)
        #expect(CLIOpenOptions(showSidebar: false).requiresPaths)
    }

    /// フィールドを足したときに、requiresPaths とウィンドウへの適用
    /// (ViewerWindowManager の CLI オプション適用)の両方の更新を強制するためのトリップワイヤ。
    /// ここが落ちたら、増えたフィールドを requiresPaths とオプション適用の双方へ配線すること。
    @Test("CLIOpenOptions のフィールド集合は既知のものと一致する")
    func optionFieldsAreEnumeratedExhaustively() {
        let labels = Set(Mirror(reflecting: CLIOpenOptions()).children.compactMap(\.label))

        #expect(labels == ["showHiddenFiles", "sortOrder", "showLineNumbers", "sourceMode", "showSidebar"])
    }
}
