@testable import befold
import Testing

/// 上書きが既定値へ混ざるときの規則(TASK-593.2)。
///
/// `SidebarDisplayOverrides` は ADR 0002 の窓ごと 4 値**すべて**を運ぶ。混ぜる場所は
/// `applied(to:)` の 1 箇所だけなので、値を足したときの「型には足したが混ぜ忘れた」は
/// コンパイラでは捕まらない。ここで 4 値すべてを測ることがその代わりになる。
struct SidebarDisplayOverridesTests {
    private let base = SidebarDisplaySettings(
        showHiddenFiles: false, showChangedFilesOnly: false,
        layoutMode: .drillDown, sortOrder: .foldersFirst
    )

    @Test("指定なしなら既定値がそのまま残る")
    func noneKeepsSettings() {
        #expect(SidebarDisplayOverrides.none.applied(to: base) == base)
    }

    @Test("4 値それぞれが単独で上書きされる")
    func eachValueOverridesIndependently() {
        #expect(
            SidebarDisplayOverrides(sortOrder: .alphabetical).applied(to: base).sortOrder
                == .alphabetical
        )
        #expect(SidebarDisplayOverrides(showHiddenFiles: true).applied(to: base).showHiddenFiles)
        #expect(
            SidebarDisplayOverrides(showChangedFilesOnly: true)
                .applied(to: base).showChangedFilesOnly
        )
        #expect(
            SidebarDisplayOverrides(layoutMode: .tree).applied(to: base).layoutMode == .tree
        )
    }

    @Test("単独の上書きは他の 3 値に触らない")
    func overridingOneValueLeavesTheRest() {
        let merged = SidebarDisplayOverrides(layoutMode: .tree).applied(to: base)

        #expect(merged.sortOrder == base.sortOrder)
        #expect(merged.showHiddenFiles == base.showHiddenFiles)
        #expect(merged.showChangedFilesOnly == base.showChangedFilesOnly)
    }

    @Test("4 値すべてを指定すると既定値は 1 つも残らない")
    func allValuesOverride() {
        let overrides = SidebarDisplayOverrides(
            sortOrder: .alphabetical, showHiddenFiles: true,
            showChangedFilesOnly: true, layoutMode: .tree
        )

        let merged = overrides.applied(to: base)

        #expect(
            merged == SidebarDisplaySettings(
                showHiddenFiles: true, showChangedFilesOnly: true,
                layoutMode: .tree, sortOrder: .alphabetical
            )
        )
    }
}
