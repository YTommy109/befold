@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct PerFileStateStoreTests {
    @Test("migrate は zoom / sourceMode / scrollPosition に加えてサイドバー開閉状態も引き継ぐ")
    func migrateAlsoMigratesSidebarCollapsedState() {
        let defaults = makeIsolatedDefaults(prefix: "PerFileStateStoreTests")
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = PerFileStateStore(defaults: defaults)
        store.sidebar.setCollapsed(false, for: old)

        store.migrate(from: old, to: new)

        #expect(store.sidebar.isCollapsed(for: new) == false)
        #expect(store.sidebar.isCollapsed(for: old) == nil)
    }
}
