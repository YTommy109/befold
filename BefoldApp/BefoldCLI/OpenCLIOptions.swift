import ArgumentParser
import BefoldKit
import Foundation

/// `--sort` の値としてそのまま受け取れるようにする。RawValue == String かつ CaseIterable のため
/// ExpressibleByArgument の既定実装だけで足り、help の候補値表示(values: ...)もそこから導かれる。
/// 適合を BefoldCLI 側でなくここに置くのは、共有ライブラリに ArgumentParser を持ち込まないため。
extension CLISortOrderOption: ExpressibleByArgument {}

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

/// ソース/プレビュー/差分の表示モードを排他的に受ける。詳細は `HiddenFilesFlag` を参照。
enum DisplayModeFlag: EnumerableFlag {
    case source
    case preview
    case diff

    static func name(for value: Self) -> NameSpecification {
        switch value {
        case .source: [.customLong("source")]
        case .preview: [.customLong("preview")]
        case .diff: [.customLong("diff")]
        }
    }

    static func help(for value: Self) -> ArgumentHelp? {
        switch value {
        case .source: "Open in source view mode."
        case .preview: "Open in preview mode."
        case .diff: "Open in diff mode (git changes against the --compare base)."
        }
    }
}

extension DisplayModeFlag {
    var option: CLIDisplayModeOption {
        switch self {
        case .source: .source
        case .preview: .rendered
        case .diff: .diff
        }
    }
}

extension CLIComparisonTargetOption: ExpressibleByArgument {}

/// ファイルを開く際の表示オプション定義。BefoldCLICommand が単一の @OptionGroup として保持する
/// (root 以外にこれを共有する ParsableCommand は存在しないため、
/// サブコマンド名の前でフラグが黙殺される問題は構造的に起きない)。
///
/// 両立しないフラグのペア(hidden-files/no-hidden-files など)は EnumerableFlag の単一値
/// @Flag として宣言することで、同時指定を ArgumentParser のパース段階で構造的に弾く。
/// 各フラグ未指定は nil(保存済み設定・既定値を維持)を表す 3 値意味論を保つ。
///
/// パース結果は `cliOpenOptions` で ArgumentParser 非依存の `CLIOpenOptions`(BefoldCLI)へ
/// 変換して受け渡す。この境界より内側にだけ ArgumentParser を閉じ込める。
public struct OpenCLIOptions: ParsableArguments {
    @Flag var hiddenFiles: HiddenFilesFlag?

    @Option(name: .customLong("sort"), help: "Specify the sidebar sort order.")
    var sortOrder: CLISortOrderOption?

    @Flag var lineNumbers: LineNumbersFlag?

    @Flag var displayMode: DisplayModeFlag?

    @Option(
        name: .customLong("compare"),
        help: "Specify the diff base: parent-branch, default-branch or head. Requires --diff."
    )
    var comparisonTarget: CLIComparisonTargetOption?

    @Option(
        name: .customLong("line"),
        help: "Scroll to the given line (1-based) in source view. Implies --source; takes exactly one path."
    )
    var line: Int?

    @Flag(name: .customLong("new-window"), help: "Open in a new window instead of reusing an existing one.")
    var newWindow = false

    @Flag var sidebar: SidebarVisibilityFlag?

    public init() {}

    public var cliOpenOptions: CLIOpenOptions {
        CLIOpenOptions(
            showHiddenFiles: hiddenFiles.map { $0 == .hiddenFiles },
            sortOrder: sortOrder,
            showLineNumbers: lineNumbers.map { $0 == .lineNumbers },
            // --line は行番号のあるソース表示でしか意味を持たないので、表示モード未指定ならソースにする。
            displayMode: displayMode.map(\.option) ?? (line == nil ? nil : .source),
            comparisonTarget: comparisonTarget,
            showSidebar: sidebar.map { $0 == .sidebar },
            line: line,
            opensInNewWindow: newWindow
        )
    }
}
