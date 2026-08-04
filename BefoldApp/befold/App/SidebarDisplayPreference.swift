import Foundation

/// サイドバーの一覧表示に関する ON/OFF を UserDefaults に永続化する。
/// ZoomStore と同じ「注入して共有する」パターンに倣い、全ウィンドウで
/// 同一インスタンスを共有することでアプリ全体・全ウィンドウ共通の状態にする。
@MainActor
final class SidebarDisplayPreference {
    private let defaults: UserDefaults
    private static let showHiddenFilesKey = "ShowHiddenFiles"
    private static let showChangedFilesOnlyKey = "ShowChangedFilesOnly"

    /// 不可視ファイル(ドットファイル)を一覧に出すか。
    var showHiddenFiles: Bool {
        didSet {
            defaults.set(showHiddenFiles, forKey: Self.showHiddenFilesKey)
        }
    }

    /// git 変更のあるファイルだけに一覧を絞るか。
    var showChangedFilesOnly: Bool {
        didSet {
            defaults.set(showChangedFilesOnly, forKey: Self.showChangedFilesOnlyKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showHiddenFiles = defaults.bool(forKey: Self.showHiddenFilesKey)
        showChangedFilesOnly = defaults.bool(forKey: Self.showChangedFilesOnlyKey)
    }
}
