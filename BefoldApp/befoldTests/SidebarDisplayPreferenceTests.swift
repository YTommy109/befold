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

    /// 機能の有無は別テストで固定する。ここは永続化だけを見たいので、周囲の
    /// FeatureGate 値(DEBUG かどうか)に結果が左右されないよう常に注入する(TASK-290)。
    private func makePreference(
        defaults: UserDefaults, available: Bool = true
    ) -> SidebarDisplayPreference {
        SidebarDisplayPreference(defaults: defaults, isChangedFilesOnlyAvailable: available)
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

    /// 機能が無効なビルドでは切り替える手段が露出しないため、保存値が ON でも
    /// OFF として起動する。保存値は残すので dev ビルドへ戻れば ON で復帰する(TASK-284)。
    @Test("機能が無効なビルドでは、保存値が ON でも変更ファイル絞り込みは OFF で読まれる")
    func changedFilesOnlyReadsOffWhenFeatureUnavailable() {
        let defaults = makeDefaults()
        SidebarDisplayPreference(defaults: defaults).showChangedFilesOnly = true

        let unavailable = SidebarDisplayPreference(
            defaults: defaults, isChangedFilesOnlyAvailable: false
        )

        #expect(unavailable.showChangedFilesOnly == false)
        // 保存値は書き換えない。機能が使えるビルドで読めば ON のまま。
        let available = SidebarDisplayPreference(
            defaults: defaults, isChangedFilesOnlyAvailable: true
        )
        #expect(available.showChangedFilesOnly == true)
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
