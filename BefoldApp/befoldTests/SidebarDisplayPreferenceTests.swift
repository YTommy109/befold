@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct SidebarDisplayPreferenceTests {
    private func makeDefaults() -> UserDefaults {
        makeIsolatedDefaults(prefix: "SidebarDisplayPreferenceTests")
    }

    @Test("デフォルトは非表示(false)")
    func defaultsToHiddenWhenUnsaved() {
        let preference = SidebarDisplayPreference(defaults: makeDefaults())

        #expect(preference.showHiddenFiles == false)
    }

    @Test("トグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func togglePersistsAcrossInstances() {
        let defaults = makeDefaults()

        SidebarDisplayPreference(defaults: defaults).showHiddenFiles = true

        #expect(SidebarDisplayPreference(defaults: defaults).showHiddenFiles == true)
    }

    @Test("変更ファイル絞り込みのデフォルトは OFF")
    func changedFilesOnlyDefaultsToOff() {
        let preference = SidebarDisplayPreference(defaults: makeDefaults())

        #expect(preference.showChangedFilesOnly == false)
    }

    @Test("変更ファイル絞り込みも永続化され、次のインスタンスへ引き継がれる")
    func changedFilesOnlyPersistsAcrossInstances() {
        let defaults = makeDefaults()

        SidebarDisplayPreference(defaults: defaults).showChangedFilesOnly = true

        #expect(SidebarDisplayPreference(defaults: defaults).showChangedFilesOnly == true)
    }

    @Test("2 つの設定は互いに独立して保存される")
    func settingsArePersistedIndependently() {
        let defaults = makeDefaults()

        SidebarDisplayPreference(defaults: defaults).showChangedFilesOnly = true

        let restored = SidebarDisplayPreference(defaults: defaults)
        #expect(restored.showHiddenFiles == false)
        #expect(restored.showChangedFilesOnly == true)
    }
}
