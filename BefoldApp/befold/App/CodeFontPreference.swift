import Foundation

/// ソースコードビューの等幅フォント設定（ファミリー・サイズ）を UserDefaults に永続化する。
/// SidebarDisplayPreference と同じ「注入して全ウィンドウで共有する」パターン。
@MainActor
final class CodeFontPreference {
    static let minPoints: Double = 6
    static let maxPoints: Double = 32
    /// 既定サイズ。現状の見た目（本文16px × 0.75 = 12px）に近い値。
    static let defaultPoints: Double = 10

    private let defaults: UserDefaults
    private static let familyKey = "CodeFontFamily"
    private static let sizeKey = "CodeFontSizePoints"

    /// nil はシステム既定（ハードコード等幅スタックへフォールバック）。
    var fontFamily: String? {
        didSet { defaults.set(fontFamily, forKey: Self.familyKey) }
    }

    /// nil は未カスタマイズ（CSS 側の calc(本文*0.75) フォールバックへ委ね、
    /// アクセシビリティ文字サイズへの追従を保つ）。設定 UI で明示的に変更した場合のみ値を持つ。
    var fontSizePoints: Double? {
        didSet {
            guard let points = fontSizePoints else {
                defaults.removeObject(forKey: Self.sizeKey)
                return
            }
            let clamped = Self.clamp(points)
            guard clamped == points else {
                fontSizePoints = clamped
                return
            }
            defaults.set(clamped, forKey: Self.sizeKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontFamily = defaults.string(forKey: Self.familyKey)
        fontSizePoints = (defaults.object(forKey: Self.sizeKey) as? Double).map(Self.clamp)
    }

    private static func clamp(_ points: Double) -> Double {
        guard points >= minPoints, points <= maxPoints else { return defaultPoints }
        return points
    }
}
