@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct SidebarDisplayDefaultsTests {
    private func makeDefaults() -> UserDefaults {
        makeIsolatedDefaults(prefix: "SidebarDisplayDefaultsTests")
    }

    @Test("デフォルトは非表示(false)")
    func defaultsToHiddenWhenUnsaved() {
        let preference = SidebarDisplayDefaults(defaults: makeDefaults())

        #expect(preference.settings.showHiddenFiles == false)
    }

    @Test("トグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func togglePersistsAcrossInstances() {
        let defaults = makeDefaults()

        SidebarDisplayDefaults(defaults: defaults).record { $0.showHiddenFiles = true }

        #expect(SidebarDisplayDefaults(defaults: defaults).settings.showHiddenFiles == true)
    }

    private func makePreference(defaults: UserDefaults) -> SidebarDisplayDefaults {
        SidebarDisplayDefaults(defaults: defaults)
    }

    @Test("変更ファイル絞り込みのデフォルトは OFF")
    func changedFilesOnlyDefaultsToOff() {
        let preference = makePreference(defaults: makeDefaults())

        #expect(preference.settings.showChangedFilesOnly == false)
    }

    @Test("変更ファイル絞り込みも永続化され、次のインスタンスへ引き継がれる")
    func changedFilesOnlyPersistsAcrossInstances() {
        let defaults = makeDefaults()

        makePreference(defaults: defaults).record { $0.showChangedFilesOnly = true }

        #expect(makePreference(defaults: defaults).settings.showChangedFilesOnly == true)
    }

    /// 保存値の ON は、ビルド構成によらずそのまま ON として読む(TASK-187 で降格を撤去)。
    @Test("保存値が ON なら変更ファイル絞り込みはそのまま ON で読まれる")
    func changedFilesOnlyReadsStoredValueAsIs() {
        let defaults = makeDefaults()
        SidebarDisplayDefaults(defaults: defaults).record { $0.showChangedFilesOnly = true }

        #expect(SidebarDisplayDefaults(defaults: defaults).settings.showChangedFilesOnly == true)
    }

    @Test("並び順のデフォルトはフォルダー優先")
    func sortOrderDefaultsToFoldersFirst() {
        #expect(SidebarDisplayDefaults(defaults: makeDefaults()).settings.sortOrder == .foldersFirst)
    }

    @Test("並び順は永続化され、次のインスタンスへ引き継がれる")
    func sortOrderPersistsAcrossInstances() {
        let defaults = makeDefaults()

        SidebarDisplayDefaults(defaults: defaults).record { $0.sortOrder = .alphabetical }

        #expect(SidebarDisplayDefaults(defaults: defaults).settings.sortOrder == .alphabetical)
    }

    /// 保存値が壊れていても既定へ倒す。ここが nil 落ちすると起動できなくなる。
    @Test("並び順の保存値が未知の文字列ならフォルダー優先へ倒す")
    func sortOrderFallsBackForUnknownRawValue() {
        let defaults = makeDefaults()
        defaults.set("bogus", forKey: "SidebarSortOrder")

        #expect(SidebarDisplayDefaults(defaults: defaults).settings.sortOrder == .foldersFirst)
    }

    @Test("2 つの設定は互いに独立して保存される")
    func settingsArePersistedIndependently() {
        let defaults = makeDefaults()

        makePreference(defaults: defaults).record { $0.showChangedFilesOnly = true }

        let restored = makePreference(defaults: defaults)
        #expect(restored.settings.showHiddenFiles == false)
        #expect(restored.settings.showChangedFilesOnly == true)
    }
}
