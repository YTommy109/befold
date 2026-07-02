import Foundation

/// ファイル毎の表示倍率を UserDefaults に永続化し、再起動後の復元に使う。
/// パスはシンボリックリンク解決後の絶対パスで正規化して保持する。
@MainActor
final class ZoomStore {
    static let defaultZoom = 1.0
    /// viewer.js の ZOOM_MIN / ZOOM_MAX と同値。
    static let minZoom = 0.5
    static let maxZoom = 2.0
    private static let defaultsKey = "ViewerZoomLevels"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 指定ファイルの保存済み倍率を返す。保存がなければデフォルト、範囲外は clamp する。
    func zoom(for url: URL) -> Double {
        guard let zoom = savedZooms()[url.normalizedPathKey] else { return Self.defaultZoom }
        return min(Self.maxZoom, max(Self.minZoom, zoom))
    }

    /// 指定ファイルの倍率を保存する。
    /// clamp は読み取り時（zoom(for:)）に行うため、書き込み時はそのまま保存する。
    func setZoom(_ zoom: Double, for url: URL) {
        var zooms = savedZooms()
        zooms[url.normalizedPathKey] = zoom
        defaults.set(zooms, forKey: Self.defaultsKey)
    }

    private func savedZooms() -> [String: Double] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
    }
}
