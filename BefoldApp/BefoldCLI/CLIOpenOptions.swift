import ArgumentParser
import Foundation

/// サイドバー/フォルダー一覧の並び順。`SortOrder`(Viewer 層)に対応する CLI 向けの値。
public enum CLISortOrderOption: String, CaseIterable, Equatable, Codable, ExpressibleByArgument, Sendable {
    case foldersFirst = "folders-first"
    case alphabetical
}

/// `-h`/`--help`・`--check`/`--bookmark` 以外の起動オプション。未指定の項目は既存の保存済み設定・既定値を維持する。
public struct CLIOpenOptions: Equatable, Codable, Sendable {
    public var showHiddenFiles: Bool?
    public var sortOrder: CLISortOrderOption?
    public var showLineNumbers: Bool?
    public var sourceMode: Bool?
    public var showSidebar: Bool?

    public init(
        showHiddenFiles: Bool? = nil,
        sortOrder: CLISortOrderOption? = nil,
        showLineNumbers: Bool? = nil,
        sourceMode: Bool? = nil,
        showSidebar: Bool? = nil
    ) {
        self.showHiddenFiles = showHiddenFiles
        self.sortOrder = sortOrder
        self.showLineNumbers = showLineNumbers
        self.sourceMode = sourceMode
        self.showSidebar = showSidebar
    }
}

/// 隠しファイル表示の ON/OFF を排他的に受ける。`@Flag var x: HiddenFilesFlag?` として
/// 単一値で宣言すると、両フラグの同時指定は ArgumentParser のパース段階でエラーになる(構造的排他)。
/// 未指定なら nil(保存済み設定を維持)。
enum HiddenFilesFlag: EnumerableFlag {
    case hiddenFiles
    case noHiddenFiles

    static func name(for value: Self) -> NameSpecification {
        switch value {
        case .hiddenFiles: [.customLong("hidden-files")]
        case .noHiddenFiles: [.customLong("no-hidden-files")]
        }
    }

    static func help(for value: Self) -> ArgumentHelp? {
        switch value {
        case .hiddenFiles: "Show hidden files in the sidebar."
        case .noHiddenFiles: "Don't show hidden files in the sidebar."
        }
    }
}

/// 行番号表示の ON/OFF を排他的に受ける。詳細は `HiddenFilesFlag` を参照。
enum LineNumbersFlag: EnumerableFlag {
    case lineNumbers
    case noLineNumbers

    static func name(for value: Self) -> NameSpecification {
        switch value {
        case .lineNumbers: [.customLong("line-numbers")]
        case .noLineNumbers: [.customLong("no-line-numbers")]
        }
    }

    static func help(for value: Self) -> ArgumentHelp? {
        switch value {
        case .lineNumbers: "Show line numbers in source view."
        case .noLineNumbers: "Don't show line numbers in source view."
        }
    }
}

/// サイドバーの表示/非表示を排他的に受ける。詳細は `HiddenFilesFlag` を参照。
enum SidebarVisibilityFlag: EnumerableFlag {
    case sidebar
    case noSidebar

    static func name(for value: Self) -> NameSpecification {
        switch value {
        case .sidebar: [.customLong("sidebar")]
        case .noSidebar: [.customLong("no-sidebar")]
        }
    }

    static func help(for value: Self) -> ArgumentHelp? {
        switch value {
        case .sidebar: "Open with the sidebar shown."
        case .noSidebar: "Open with the sidebar hidden."
        }
    }
}

/// ソース/プレビュー表示モードを排他的に受ける。詳細は `HiddenFilesFlag` を参照。
/// `.source` が true(ソースモード)に対応する。
enum SourceModeFlag: EnumerableFlag {
    case source
    case preview

    static func name(for value: Self) -> NameSpecification {
        switch value {
        case .source: [.customLong("source")]
        case .preview: [.customLong("preview")]
        }
    }

    static func help(for value: Self) -> ArgumentHelp? {
        switch value {
        case .source: "Open in source view mode."
        case .preview: "Open in preview mode."
        }
    }
}

/// ファイルを開く際の表示オプション定義。BefoldCLICommand が単一の @OptionGroup として保持する
/// (root 以外にこれを共有する ParsableCommand は存在しないため、
/// サブコマンド名の前でフラグが黙殺される問題は構造的に起きない)。
///
/// 両立しないフラグのペア(hidden-files/no-hidden-files など)は EnumerableFlag の単一値
/// @Flag として宣言することで、同時指定を ArgumentParser のパース段階で構造的に弾く。
/// 各フラグ未指定は nil(保存済み設定・既定値を維持)を表す 3 値意味論を保つ。
public struct OpenCLIOptions: ParsableArguments {
    @Flag var hiddenFiles: HiddenFilesFlag?

    @Option(name: .customLong("sort"), help: "Specify the sidebar sort order.")
    var sortOrder: CLISortOrderOption?

    @Flag var lineNumbers: LineNumbersFlag?

    @Flag var sourceMode: SourceModeFlag?

    @Flag var sidebar: SidebarVisibilityFlag?

    public init() {}

    public var cliOpenOptions: CLIOpenOptions {
        CLIOpenOptions(
            showHiddenFiles: hiddenFiles.map { $0 == .hiddenFiles },
            sortOrder: sortOrder,
            showLineNumbers: lineNumbers.map { $0 == .lineNumbers },
            sourceMode: sourceMode.map { $0 == .source },
            showSidebar: sidebar.map { $0 == .sidebar }
        )
    }
}
