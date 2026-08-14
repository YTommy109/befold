import Foundation

/// サイドバー表示 4 値の**アプリ全体の既定値**を UserDefaults に永続化する。
///
/// 保持する値の意味は「次に開くウィンドウの出発点」であって、開いている窓の現在値ではない
/// (ADR 0002「窓の状態」)。ライブ値は窓ごとの `FileListModel` にあり、窓はこの型を
/// 参照しない——窓が受け取るのは初期値の `SidebarDisplaySettings`(値型)と、
/// 書き戻し用の `SidebarDisplayDefaultsRecording`(読み取りを持たないプロトコル)だけ。
///
/// TASK-480 以前は全ウィンドウで同一インスタンスを共有する「アプリ全体の現在値」だった。
/// キー名と値の形は変えていないため、既存ユーザーの保存値はそのまま初期値として引き継がれる。
@MainActor
final class SidebarDisplayDefaults: SidebarDisplayDefaultsProviding {
    private let defaults: UserDefaults
    private static let showHiddenFilesKey = "ShowHiddenFiles"
    private static let showChangedFilesOnlyKey = "ShowChangedFilesOnly"
    private static let layoutModeKey = "SidebarLayoutMode"
    private static let sortOrderKey = "SidebarSortOrder"

    /// 新しく開くウィンドウの初期値。**読むのは窓の生成時の 1 回だけ。**
    private(set) var settings: SidebarDisplaySettings

    /// 保存値はいずれもそのまま読む(表示の可否で降格しない)。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = SidebarDisplaySettings(
            showHiddenFiles: defaults.bool(forKey: Self.showHiddenFilesKey),
            showChangedFilesOnly: defaults.bool(forKey: Self.showChangedFilesOnlyKey),
            layoutMode: SidebarLayoutMode.stored(defaults.string(forKey: Self.layoutModeKey)),
            sortOrder: SortOrder.stored(defaults.string(forKey: Self.sortOrderKey))
        )
    }

    /// 4 値の最新値を既定値として記録する。窓が値を変えるたびに呼ばれ、後勝ちでよい。
    func record(_ settings: SidebarDisplaySettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        defaults.set(settings.showHiddenFiles, forKey: Self.showHiddenFilesKey)
        defaults.set(settings.showChangedFilesOnly, forKey: Self.showChangedFilesOnlyKey)
        defaults.set(settings.layoutMode.rawValue, forKey: Self.layoutModeKey)
        defaults.set(settings.sortOrder.rawValue, forKey: Self.sortOrderKey)
    }
}
