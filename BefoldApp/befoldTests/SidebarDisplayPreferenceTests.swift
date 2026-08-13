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

    private func makePreference(defaults: UserDefaults) -> SidebarDisplayPreference {
        SidebarDisplayPreference(defaults: defaults)
    }

    @Test("変更ファイル絞り込みのデフォルトは OFF")
    func changedFilesOnlyDefaultsToOff() {
        let preference = makePreference(defaults: makeDefaults())

        #expect(preference.showChangedFilesOnly == false)
    }

    @Test("変更ファイル絞り込みも永続化され、次のインスタンスへ引き継がれる")
    func changedFilesOnlyPersistsAcrossInstances() {
        let defaults = makeDefaults()

        makePreference(defaults: defaults).showChangedFilesOnly = true

        #expect(makePreference(defaults: defaults).showChangedFilesOnly == true)
    }

    /// 保存値の ON は、ビルド構成によらずそのまま ON として読む(TASK-187 で降格を撤去)。
    @Test("保存値が ON なら変更ファイル絞り込みはそのまま ON で読まれる")
    func changedFilesOnlyReadsStoredValueAsIs() {
        let defaults = makeDefaults()
        SidebarDisplayPreference(defaults: defaults).showChangedFilesOnly = true

        #expect(SidebarDisplayPreference(defaults: defaults).showChangedFilesOnly == true)
    }

    @Test("並び順のデフォルトはフォルダー優先")
    func sortOrderDefaultsToFoldersFirst() {
        #expect(SidebarDisplayPreference(defaults: makeDefaults()).sortOrder == .foldersFirst)
    }

    @Test("並び順は永続化され、次のインスタンスへ引き継がれる")
    func sortOrderPersistsAcrossInstances() {
        let defaults = makeDefaults()

        SidebarDisplayPreference(defaults: defaults).sortOrder = .alphabetical

        #expect(SidebarDisplayPreference(defaults: defaults).sortOrder == .alphabetical)
    }

    /// 保存値が壊れていても既定へ倒す。ここが nil 落ちすると起動できなくなる。
    @Test("並び順の保存値が未知の文字列ならフォルダー優先へ倒す")
    func sortOrderFallsBackForUnknownRawValue() {
        let defaults = makeDefaults()
        defaults.set("bogus", forKey: "SidebarSortOrder")

        #expect(SidebarDisplayPreference(defaults: defaults).sortOrder == .foldersFirst)
    }

    @Test("2 つの設定は互いに独立して保存される")
    func settingsArePersistedIndependently() {
        let defaults = makeDefaults()

        makePreference(defaults: defaults).showChangedFilesOnly = true

        let restored = makePreference(defaults: defaults)
        #expect(restored.showHiddenFiles == false)
        #expect(restored.showChangedFilesOnly == true)
    }
}
