import Foundation

/// サイドバー/フォルダー一覧の並び順。`SortOrder`(Viewer 層)に対応する CLI 向けの値。
/// CLI 引数としてのパース(ExpressibleByArgument 適合)は befold-cli 側の extension で与える。
public enum CLISortOrderOption: String, CaseIterable, Equatable, Codable, Sendable {
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
