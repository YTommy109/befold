@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct SidebarStateStoreTests {
    @Test
    func isCollapsedIsNilWhenUnsaved() {
        let store = SidebarStateStore(defaults: makeIsolatedDefaults(prefix: "SidebarStateStoreTests"))

        #expect(store.isCollapsed(for: URL(fileURLWithPath: "/tmp/diagram.mmd")) == nil)
    }

    @Test
    func setCollapsedPersistsPerFileAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        SidebarStateStore(defaults: defaults).setCollapsed(false, for: url)

        #expect(SidebarStateStore(defaults: defaults).isCollapsed(for: url) == false)
    }

    @Test
    func collapsedStatesAreIndependentPerFile() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let first = URL(fileURLWithPath: "/tmp/first.mmd")
        let second = URL(fileURLWithPath: "/tmp/second.md")
        let store = SidebarStateStore(defaults: defaults)

        store.setCollapsed(false, for: first)
        store.setCollapsed(true, for: second)

        #expect(store.isCollapsed(for: first) == false)
        #expect(store.isCollapsed(for: second) == true)
    }

    @Test("rename で旧パスの開閉状態が新パスへ引き継がれ旧キーは消える")
    func migrateCollapsedMovesValueToNewKey() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = SidebarStateStore(defaults: defaults)
        store.setCollapsed(false, for: old)

        store.migrateCollapsed(from: old, to: new)

        #expect(store.isCollapsed(for: new) == false)
        #expect(store.isCollapsed(for: old) == nil)
    }

    @Test("保存値のないファイルの migrate は新パスに影響しない")
    func migrateCollapsedWithoutSavedValueIsNoop() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = SidebarStateStore(defaults: defaults)
        store.setCollapsed(false, for: new)

        store.migrateCollapsed(from: old, to: new)

        #expect(store.isCollapsed(for: new) == false)
    }

    @Test("シンボリックリンク経由でも同一ファイルとして扱う")
    func symlinkResolvesToSamePath() throws {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let tmp = try TempDir(prefix: "SidebarStateStoreTests")
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()
        let store = SidebarStateStore(defaults: defaults)

        store.setCollapsed(false, for: link)

        #expect(store.isCollapsed(for: real) == false)
    }

    @Test("未操作時は閉じた状態(true)がデフォルト")
    func lastToggledCollapsedDefaultsToTrueWhenUnsaved() {
        let store = SidebarStateStore(defaults: makeIsolatedDefaults(prefix: "SidebarStateStoreTests"))

        #expect(store.lastToggledCollapsed == true)
    }

    @Test("recordToggle はファイル単位の状態と最後の操作状態の両方を更新する")
    func recordToggleUpdatesBothPerFileAndLastToggled() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        SidebarStateStore(defaults: defaults).recordToggle(false, for: url)

        let reloaded = SidebarStateStore(defaults: defaults)
        #expect(reloaded.isCollapsed(for: url) == false)
        #expect(reloaded.lastToggledCollapsed == false)
    }

    @Test("setCollapsed(ウィンドウオープン時の記録)は最後の操作状態を書き換えない")
    func setCollapsedDoesNotAffectLastToggledCollapsed() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let store = SidebarStateStore(defaults: defaults)
        store.recordToggle(false, for: URL(fileURLWithPath: "/tmp/a.mmd"))

        store.setCollapsed(true, for: URL(fileURLWithPath: "/tmp/b.mmd"))

        #expect(store.lastToggledCollapsed == false)
    }

    @Test("自ファイルの保存値があればそれを使う")
    func initialCollapsedUsesOwnSavedValueWhenPresent() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let url = URL(fileURLWithPath: "/tmp/own.mmd")
        let store = SidebarStateStore(defaults: defaults)
        store.setCollapsed(false, for: url)

        #expect(store.initialCollapsed(for: url, lastActivePathKey: "/tmp/other.mmd") == false)
    }

    @Test("自ファイルの保存値がなければ直近アクティブだったウィンドウの状態を使う")
    func initialCollapsedFallsBackToLastActiveWindowState() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let store = SidebarStateStore(defaults: defaults)
        let activePath = URL(fileURLWithPath: "/tmp/active.mmd")
        store.setCollapsed(false, for: activePath)

        let result = store.initialCollapsed(
            for: URL(fileURLWithPath: "/tmp/new.mmd"), lastActivePathKey: activePath.normalizedPathKey
        )

        #expect(result == false)
    }

    @Test("直近アクティブなウィンドウの記録も自ファイルの保存値もなければ最後の操作状態を使う")
    func initialCollapsedFallsBackToLastToggledCollapsed() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarStateStoreTests")
        let store = SidebarStateStore(defaults: defaults)
        store.recordToggle(false, for: URL(fileURLWithPath: "/tmp/somewhere-else.mmd"))

        let result = store.initialCollapsed(for: URL(fileURLWithPath: "/tmp/new.mmd"), lastActivePathKey: nil)

        #expect(result == false)
    }
}
