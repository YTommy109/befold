import BefoldKit
import Foundation

/// ファイル毎のスクロール位置(scrollTop)を UserDefaults に永続化し、
/// ファイル切替時・再起動後の復元に使う。ZoomStore / SourceModeStore と同じ
/// PathKeyedDictionary 基盤を使う。レンダリング表示とソース表示は DOM 構造が異なり
/// スクロール位置に連続性がないため、rendered/source を別々のストレージへ独立保存する。
@MainActor
final class ScrollPositionStore {
    private let renderedPositions: PathKeyedDictionary<Double>
    private let sourcePositions: PathKeyedDictionary<Double>

    init(defaults: UserDefaults = .standard) {
        renderedPositions = PathKeyedDictionary(defaults: defaults, key: "ViewerScrollPositions.rendered")
        sourcePositions = PathKeyedDictionary(defaults: defaults, key: "ViewerScrollPositions.source")
    }

    /// 指定ファイル・モードの保存済みスクロール位置を返す。保存がなければ 0(先頭)。
    func scrollPosition(for url: URL, mode: ViewerBridge.ViewMode) -> Double {
        storage(for: mode).value(for: url) ?? 0
    }

    /// 指定ファイル・モードのスクロール位置を保存する。
    func setScrollPosition(_ position: Double, for url: URL, mode: ViewerBridge.ViewMode) {
        storage(for: mode).setValue(position, for: url)
    }

    /// ファイルの rename / move に伴い、旧パスの保存値(rendered/source 両方)を新パスへ引き継ぐ。
    func migrateScrollPosition(from oldURL: URL, to newURL: URL) {
        renderedPositions.migrateValue(from: oldURL, to: newURL)
        sourcePositions.migrateValue(from: oldURL, to: newURL)
    }

    private func storage(for mode: ViewerBridge.ViewMode) -> PathKeyedDictionary<Double> {
        switch mode {
        case .rendered: renderedPositions
        case .source: sourcePositions
        }
    }
}
