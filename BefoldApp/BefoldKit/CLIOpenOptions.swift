import Foundation

/// サイドバー/フォルダー一覧の並び順。`SortOrder`(Viewer 層)に対応する CLI 向けの値。
/// CLI 引数としてのパース(ExpressibleByArgument 適合)は befold-cli 側の extension で与える。
public enum CLISortOrderOption: String, CaseIterable, Equatable, Codable, Sendable {
    case foldersFirst = "folders-first"
    case alphabetical
}

/// 開いたときの表示モード。`ViewerDisplayMode`(本体側)に対応する CLI 向けの値で、
/// ワイヤ上の表現でもある。`--source` / `--preview` / `--diff` が 1 つずつ対応する。
public enum CLIDisplayModeOption: String, CaseIterable, Equatable, Codable, Sendable {
    case rendered
    case source
    case diff
}

/// 差分の比較基準。`GitComparisonTarget`(本体側)に対応する CLI 向けの値。
public enum CLIComparisonTargetOption: String, CaseIterable, Equatable, Codable, Sendable {
    case parentBranch = "parent-branch"
    case defaultBranch = "default-branch"
    case head
}

/// `-h`/`--help`・`--check`/`--bookmark` 以外の起動オプション。未指定の項目は既存の保存済み設定・既定値を維持する。
public struct CLIOpenOptions: Equatable, Codable, Sendable {
    public var showHiddenFiles: Bool?
    public var sortOrder: CLISortOrderOption?
    public var showLineNumbers: Bool?
    public var displayMode: CLIDisplayModeOption?
    public var comparisonTarget: CLIComparisonTargetOption?
    public var showSidebar: Bool?
    /// 開いた直後に表示する行(1 始まり。`--line`)。ソース表示でのみ意味を持つ。
    public var line: Int?
    /// 既存の窓を再利用せず新規ウィンドウで開く(`--new-window`)。表示設定ではなく開き方の指定。
    /// 非 Optional なのは「指定なし」と「false」を区別する意味が無いため。旧 CLI の JSON には
    /// キーが無いので、デコードは `decodeIfPresent ?? false`。
    public var opensInNewWindow: Bool

    public init(
        showHiddenFiles: Bool? = nil,
        sortOrder: CLISortOrderOption? = nil,
        showLineNumbers: Bool? = nil,
        displayMode: CLIDisplayModeOption? = nil,
        comparisonTarget: CLIComparisonTargetOption? = nil,
        showSidebar: Bool? = nil,
        line: Int? = nil,
        opensInNewWindow: Bool = false
    ) {
        self.showHiddenFiles = showHiddenFiles
        self.sortOrder = sortOrder
        self.showLineNumbers = showLineNumbers
        self.displayMode = displayMode
        self.comparisonTarget = comparisonTarget
        self.showSidebar = showSidebar
        self.line = line
        self.opensInNewWindow = opensInNewWindow
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
        sortOrder != nil || showLineNumbers != nil || displayMode != nil
            || comparisonTarget != nil || showSidebar != nil || line != nil || opensInNewWindow
    }

    private enum CodingKeys: String, CodingKey {
        case showHiddenFiles, sortOrder, showLineNumbers, displayMode, comparisonTarget, showSidebar, line,
             opensInNewWindow
        /// 旧 CLI が送っていた `--source`(true)/`--preview`(false)。読み取り専用で、送信はしない。
        case legacySourceMode = "sourceMode"
    }

    /// 旧 CLI(`sourceMode: Bool?` を送る版)からの要求を `displayMode` へ読み替える。
    /// 読み替えないと、アップデート直後の旧 CLI の `--source` が黙って捨てられる。
    /// 新旧が両方あれば新しい `displayMode` が勝つ。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles)
        sortOrder = try container.decodeIfPresent(CLISortOrderOption.self, forKey: .sortOrder)
        showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers)
        comparisonTarget = try container.decodeIfPresent(CLIComparisonTargetOption.self, forKey: .comparisonTarget)
        showSidebar = try container.decodeIfPresent(Bool.self, forKey: .showSidebar)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        opensInNewWindow = try container.decodeIfPresent(Bool.self, forKey: .opensInNewWindow) ?? false
        let legacy = try container.decodeIfPresent(Bool.self, forKey: .legacySourceMode)
        displayMode = try container.decodeIfPresent(CLIDisplayModeOption.self, forKey: .displayMode)
            ?? legacy.map { $0 ? .source : .rendered }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(showHiddenFiles, forKey: .showHiddenFiles)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(showLineNumbers, forKey: .showLineNumbers)
        try container.encodeIfPresent(displayMode, forKey: .displayMode)
        try container.encodeIfPresent(comparisonTarget, forKey: .comparisonTarget)
        try container.encodeIfPresent(showSidebar, forKey: .showSidebar)
        try container.encodeIfPresent(line, forKey: .line)
        if opensInNewWindow { try container.encode(true, forKey: .opensInNewWindow) }
    }
}
