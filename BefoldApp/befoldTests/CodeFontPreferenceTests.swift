@testable import befold
import Foundation
import Testing

@MainActor
@Suite
struct CodeFontPreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "CodeFontPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("初期状態はファミリー nil・既定サイズ")
    func defaultsWhenUnset() {
        let pref = CodeFontPreference(defaults: makeDefaults())
        #expect(pref.fontFamily == nil)
        #expect(pref.fontSizePoints == CodeFontPreference.defaultPoints)
    }

    @Test("設定値が UserDefaults に永続化され再読込で復元される")
    func persistsAndRestores() {
        let defaults = makeDefaults()
        let pref = CodeFontPreference(defaults: defaults)
        pref.fontFamily = "SF Mono"
        pref.fontSizePoints = 13

        let reloaded = CodeFontPreference(defaults: defaults)
        #expect(reloaded.fontFamily == "SF Mono")
        #expect(reloaded.fontSizePoints == 13)
    }

    @Test("範囲外サイズは読み込み時に既定へ丸める")
    func clampsOutOfRangeSizeOnLoad() {
        let defaults = makeDefaults()
        defaults.set(999.0, forKey: "CodeFontSizePoints")
        let pref = CodeFontPreference(defaults: defaults)
        #expect(pref.fontSizePoints == CodeFontPreference.defaultPoints)
    }

    @Test("post-init の範囲外サイズも didSet で既定へ丸める")
    func clampsOutOfRangeSizeOnAssignment() {
        let pref = CodeFontPreference(defaults: makeDefaults())
        pref.fontSizePoints = 999
        #expect(pref.fontSizePoints == CodeFontPreference.defaultPoints)
    }
}
