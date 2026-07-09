@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct HiddenFilesPreferenceTests {
    @Test("デフォルトは非表示(false)")
    func defaultsToHiddenWhenUnsaved() {
        let preference = HiddenFilesPreference(defaults: makeIsolatedDefaults(prefix: "HiddenFilesPreferenceTests"))

        #expect(preference.showHiddenFiles == false)
    }

    @Test("トグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func togglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "HiddenFilesPreferenceTests")

        HiddenFilesPreference(defaults: defaults).showHiddenFiles = true

        #expect(HiddenFilesPreference(defaults: defaults).showHiddenFiles == true)
    }
}
