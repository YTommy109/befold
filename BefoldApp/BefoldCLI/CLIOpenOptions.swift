import ArgumentParser
import Foundation

/// サイドバー/フォルダー一覧の並び順。`SortOrder`(Viewer 層)に対応する CLI 向けの値。
public enum CLISortOrderOption: String, Equatable, Codable, ExpressibleByArgument, Sendable {
    case foldersFirst = "folders-first"
    case alphabetical
}

/// `-h`/`--help`・`--check`/`--bookmark` 以外の起動オプション。未指定の項目は既存の保存済み設定・既定値を維持する。
public struct CLIOpenOptions: Equatable, Codable, Sendable {
    public var showHiddenFiles: Bool?
    public var sortOrder: CLISortOrderOption?
    public var showLineNumbers: Bool?
    public var sourceMode: Bool?

    public init(
        showHiddenFiles: Bool? = nil,
        sortOrder: CLISortOrderOption? = nil,
        showLineNumbers: Bool? = nil,
        sourceMode: Bool? = nil
    ) {
        self.showHiddenFiles = showHiddenFiles
        self.sortOrder = sortOrder
        self.showLineNumbers = showLineNumbers
        self.sourceMode = sourceMode
    }
}

/// ファイルを開く際の表示オプション定義。BefoldCLICommand が単一の @OptionGroup として保持する
/// (root 以外にこれを共有する ParsableCommand は存在しないため、
/// サブコマンド名の前でフラグが黙殺される問題は構造的に起きない)。
public struct OpenCLIOptions: ParsableArguments {
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

    public init() {}

    public func validate() throws {
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

    public var cliOpenOptions: CLIOpenOptions {
        CLIOpenOptions(
            showHiddenFiles: hiddenFilesOn ? true : (hiddenFilesOff ? false : nil),
            sortOrder: sortOrder,
            showLineNumbers: lineNumbersOn ? true : (lineNumbersOff ? false : nil),
            sourceMode: sourceOn ? true : (sourceOff ? false : nil)
        )
    }
}
