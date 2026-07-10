@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct FindOptionsPreferenceTests {
    @Test("デフォルトはすべて false(大文字小文字区別なし・単語マッチなし・正規表現なし)")
    func defaultsToAllFalseWhenUnsaved() {
        let preference = FindOptionsPreference(defaults: makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests"))

        #expect(preference.caseSensitive == false)
        #expect(preference.wholeWord == false)
        #expect(preference.useRegex == false)
    }

    @Test("caseSensitive をトグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func caseSensitiveTogglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")

        FindOptionsPreference(defaults: defaults).caseSensitive = true

        #expect(FindOptionsPreference(defaults: defaults).caseSensitive == true)
    }

    @Test("wholeWord をトグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func wholeWordTogglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")

        FindOptionsPreference(defaults: defaults).wholeWord = true

        #expect(FindOptionsPreference(defaults: defaults).wholeWord == true)
    }

    @Test("useRegex をトグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func useRegexTogglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")

        FindOptionsPreference(defaults: defaults).useRegex = true

        #expect(FindOptionsPreference(defaults: defaults).useRegex == true)
    }
}
