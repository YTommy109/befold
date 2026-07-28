import Foundation

/// ソースコードビューの等幅フォント設定（ファミリー・サイズ）を UserDefaults に永続化する。
/// HiddenFilesPreference と同じ「注入して全ウィンドウで共有する」パターン。
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

    var fontSizePoints: Double {
        didSet {
            fontSizePoints = Self.clamp(fontSizePoints)
            defaults.set(fontSizePoints, forKey: Self.sizeKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontFamily = defaults.string(forKey: Self.familyKey)
        let stored = defaults.object(forKey: Self.sizeKey) as? Double
        fontSizePoints = stored.map(Self.clamp) ?? Self.defaultPoints
    }

    private static func clamp(_ points: Double) -> Double {
        guard points >= minPoints, points <= maxPoints else { return defaultPoints }
        return points
    }
}
