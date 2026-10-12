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

    /// 開く対象(パス)を伴わなければ意味を持たない指定が含まれるか。
    ///
    /// 表示オプションはどれも「その文書をどう表示するか」の指定なので、対象が無ければ
    /// 適用先が無い。`BefoldCLICommand.validate()` はこれを見てパース段階で弾く。
    /// `showHiddenFiles` だけはアプリ全体設定(サイドバーの不可視ファイル表示)のため対象を要さない。
    ///
    /// `self != CLIOpenOptions()` で代用してはいけない。それでは `--hidden-files` 単独の
    /// 指定まで弾いてしまう。`CLIAppLauncher` が使う `options == CLIOpenOptions()` は
    /// 「そもそも GUI へ転送するか」の別判定であり、この述語とは目的が違う。
    public var requiresPaths: Bool {
        sortOrder != nil || showLineNumbers != nil || sourceMode != nil || showSidebar != nil
    }
}
