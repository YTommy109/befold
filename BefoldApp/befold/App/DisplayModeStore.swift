import BefoldKit
import Foundation

/// ファイル毎の表示モード（レンダリング / ソース / 差分）を UserDefaults に永続化し、
/// ファイル切替時・再起動後の復元に使う。ZoomStore と同じ PathKeyedDictionary 基盤を使う。
///
/// 差分の ON/OFF もここに載せる。以前はアプリ全体（`DiffDisplayPreference.isEnabled`）で
/// 持っていたため、ファイル A で差分を選んで B へ移ると、B はレンダリング表示なのに
/// 差分フラグだけ立った状態になっていた。粒度をソース表示と揃えることでこれを無くす。
@MainActor
final class DisplayModeStore {
    private let modes: PathKeyedDictionary<String>

    /// 表示モードを 1 値で持つ以前に使っていた「ソース表示 Bool」の保存キー。
    /// 新キーが未設定のときだけ読み、`true` を `.source` として引き継ぐ。
    private static let legacySourceModeKey = "ViewerSourceModes"
    private static let key = "ViewerDisplayModes"

    init(defaults: UserDefaults = .standard) {
        Self.migrateLegacySourceModesIfNeeded(defaults: defaults)
        modes = PathKeyedDictionary(defaults: defaults, key: Self.key)
    }

    /// 指定ファイルの保存済み表示モードを返す。保存がなければレンダリング表示。
    func displayMode(for url: URL) -> ViewerDisplayMode {
        modes.value(for: url).flatMap(ViewerDisplayMode.init(rawValue:)) ?? .rendered
    }

    /// 指定ファイルの表示モードを保存する。
    func setDisplayMode(_ mode: ViewerDisplayMode, for url: URL) {
        modes.setValue(mode.rawValue, for: url)
    }

    /// 保存済みモードを、その種別・ビルドで実際に成立するモードまで降格して返す。
    ///
    /// - `.source` はレンダリング表示との切替を持つ種別でのみ成立する。コード種別は
    ///   そもそもレンダリング表示を持たず（`supportsSourceMode` が false）、常にソースを
    ///   出しているため、モードとしては `.rendered` のまま扱う
    /// - `.diff` の可否は `.source` とは別の条件（差分を描ける種別か・機能ゲート）で決める。
    ///   コード種別は `supportsSourceMode` が false でも差分は重ねられるため、
    ///   ここを `.source` の条件に相乗りさせるとコードファイルの差分が復元されない
    ///
    /// 降格しても保存値は書き換えない。dev ビルドへ戻れば `.diff` のまま復帰する。
    func restoredDisplayMode(for url: URL) -> ViewerDisplayMode {
        let fileType = FileType(url: url)
        let sourceOrRendered: ViewerDisplayMode = fileType.supportsSourceMode ? .source : .rendered
        switch displayMode(for: url) {
        case .rendered:
            return .rendered
        case .source:
            return sourceOrRendered
        case .diff:
            guard fileType.supportsDiffDisplay, FeatureGate.isSourceDiffEnabled else { return sourceOrRendered }
            return .diff
        }
    }

    /// ファイルの rename / move に伴い、旧パスの保存値を新パスへ引き継ぐ。
    func migrateDisplayMode(from oldURL: URL, to newURL: URL) {
        modes.migrateValue(from: oldURL, to: newURL)
    }

    /// 旧キーの「ソース表示 Bool」辞書を新キーの表示モード辞書へ 1 度だけ写す。
    /// 新キーが既にあれば何もしない（以後は新キーだけが真実の源になる）。
    private static func migrateLegacySourceModesIfNeeded(defaults: UserDefaults) {
        guard defaults.dictionary(forKey: key) == nil,
              let legacy = defaults.dictionary(forKey: legacySourceModeKey) as? [String: Bool]
        else { return }
        let migrated = legacy.mapValues { $0 ? ViewerDisplayMode.source.rawValue : ViewerDisplayMode.rendered.rawValue }
        defaults.set(migrated, forKey: key)
    }
}
