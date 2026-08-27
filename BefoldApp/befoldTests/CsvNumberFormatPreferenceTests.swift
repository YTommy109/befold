@testable import befold
import BefoldKit
import Foundation
import Testing

@MainActor
@Suite
struct CsvNumberFormatPreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "CsvNumberFormatPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("未設定なら桁区切りはオン、負の数は通常表記")
    func defaultsWhenUnset() {
        let pref = CsvNumberFormatPreference(defaults: makeDefaults())
        #expect(pref.grouping)
        #expect(pref.negativeStyle == .plain)
    }

    @Test("設定値が UserDefaults に永続化され再読込で復元される")
    func persistsAndRestores() {
        let defaults = makeDefaults()
        let pref = CsvNumberFormatPreference(defaults: defaults)
        pref.grouping = false
        pref.negativeStyle = .triangleRed

        let reloaded = CsvNumberFormatPreference(defaults: defaults)
        #expect(reloaded.grouping == false)
        #expect(reloaded.negativeStyle == .triangleRed)
    }

    /// bool(forKey:) は未設定でも false を返すため、それだけで読むと
    /// 「既定はオン」が成立しない。明示的にオフにした状態が復元されることで、
    /// 未設定との区別が効いていることを測る。
    @Test("明示的なオフは未設定と区別して復元される")
    func distinguishesExplicitOffFromUnset() {
        let defaults = makeDefaults()
        CsvNumberFormatPreference(defaults: defaults).grouping = false
        #expect(CsvNumberFormatPreference(defaults: defaults).grouping == false)

        defaults.removeObject(forKey: "CsvNumberGrouping")
        #expect(CsvNumberFormatPreference(defaults: defaults).grouping)
    }

    @Test("未知の表記名は既定へ倒す")
    func unknownStyleFallsBackToPlain() {
        let defaults = makeDefaults()
        defaults.set("bogus", forKey: "CsvNegativeStyle")
        #expect(CsvNumberFormatPreference(defaults: defaults).negativeStyle == .plain)
    }
}
