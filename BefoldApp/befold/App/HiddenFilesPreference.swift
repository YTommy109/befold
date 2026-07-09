import Foundation

/// 不可視ファイル(ドットファイル)表示のON/OFFを UserDefaults に永続化する。
/// ZoomStore と同じ「注入して共有する」パターンに倣い、全ウィンドウで
/// 同一インスタンスを共有することでアプリ全体・全ウィンドウ共通の状態にする。
@MainActor
final class HiddenFilesPreference {
    private let defaults: UserDefaults
    private static let showHiddenFilesKey = "ShowHiddenFiles"

    var showHiddenFiles: Bool {
        didSet {
            defaults.set(showHiddenFiles, forKey: Self.showHiddenFilesKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showHiddenFiles = defaults.bool(forKey: Self.showHiddenFilesKey)
    }
}
