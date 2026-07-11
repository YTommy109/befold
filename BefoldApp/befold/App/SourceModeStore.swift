import Foundation

/// ファイル毎のソース/レンダリング表示モードを UserDefaults に永続化し、
/// ファイル切替時・再起動後の復元に使う。ZoomStore と同じ PathKeyedDictionary 基盤を使う。
@MainActor
final class SourceModeStore {
    private let modes: PathKeyedDictionary<Bool>

    init(defaults: UserDefaults = .standard) {
        modes = PathKeyedDictionary(defaults: defaults, key: "ViewerSourceModes")
    }

    /// 指定ファイルの保存済みソース表示モードを返す。保存がなければ false(レンダリング表示)。
    func isSourceMode(for url: URL) -> Bool {
        modes.value(for: url) ?? false
    }

    /// 指定ファイルのソース表示モードを保存する。
    func setSourceMode(_ isSourceMode: Bool, for url: URL) {
        modes.setValue(isSourceMode, for: url)
    }

    /// 保存済みモードを返すが、ソース表示が成立しない形式では常に false。
    func restoredSourceMode(for url: URL) -> Bool {
        FileType(url: url).supportsSourceMode && isSourceMode(for: url)
    }

    /// ファイルの rename / move に伴い、旧パスの保存値を新パスへ引き継ぐ。
    func migrateSourceMode(from oldURL: URL, to newURL: URL) {
        modes.migrateValue(from: oldURL, to: newURL)
    }
}
