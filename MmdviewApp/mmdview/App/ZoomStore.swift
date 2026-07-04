import Foundation

/// ファイル毎の表示倍率を UserDefaults に永続化し、再起動後の復元に使う。
/// パスはシンボリックリンク解決後の絶対パスで正規化して保持する。
@MainActor
final class ZoomStore {
    static let defaultZoom = 1.0
    /// viewer.js の ZOOM_MIN / ZOOM_MAX と同値。
    static let minZoom = 0.5
    static let maxZoom = 2.0

    private let zooms: PathKeyedDictionary<Double>

    init(defaults: UserDefaults = .standard) {
        zooms = PathKeyedDictionary(defaults: defaults, key: "ViewerZoomLevels")
    }

    /// 指定ファイルの保存済み倍率を返す。保存がなければデフォルト、範囲外は clamp する。
    func zoom(for url: URL) -> Double {
        guard let zoom = zooms.value(for: url) else { return Self.defaultZoom }
        return min(Self.maxZoom, max(Self.minZoom, zoom))
    }

    /// 指定ファイルの倍率を保存する。
    /// clamp は読み取り時(zoom(for:))に行うため、書き込み時はそのまま保存する。
    func setZoom(_ zoom: Double, for url: URL) {
        zooms.setValue(zoom, for: url)
    }

    /// ファイルの rename / move に伴い、旧パスの倍率を新パスへ引き継ぐ。
    func migrateZoom(from oldURL: URL, to newURL: URL) {
        zooms.migrateValue(from: oldURL, to: newURL)
    }
}
