@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct SidebarStateStoreTests {
    @Test("未操作なら閉じた状態を返す")
    func lastToggledCollapsedDefaultsToTrueWhenUnsaved() {
        let store = SidebarStateStore(defaults: makeIsolatedDefaults(prefix: "SidebarStateStoreTests"))

        #expect(store.lastToggledCollapsed)
    }

    @Test("最後の操作は再起動をまたいで残り、後の操作で上書きされる")
    func recordToggleSurvivesReloadAndLastWriteWins() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")

        SidebarStateStore(defaults: defaults).recordToggle(false)
        #expect(!SidebarStateStore(defaults: defaults).lastToggledCollapsed)

        SidebarStateStore(defaults: defaults).recordToggle(true)
        #expect(SidebarStateStore(defaults: defaults).lastToggledCollapsed)
    }
}
