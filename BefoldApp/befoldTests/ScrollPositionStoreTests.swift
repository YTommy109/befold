@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct ScrollPositionStoreTests {
    @Test
    func positionIsZeroWhenUnsaved() {
        let store = ScrollPositionStore(defaults: makeIsolatedDefaults(prefix: "ScrollPositionStoreTests"))
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        #expect(store.scrollPosition(for: url, mode: .rendered) == 0)
        #expect(store.scrollPosition(for: url, mode: .source) == 0)
    }

    @Test
    func setPositionPersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "ScrollPositionStoreTests")
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        ScrollPositionStore(defaults: defaults).setScrollPosition(150.5, for: url, mode: .rendered)

        #expect(ScrollPositionStore(defaults: defaults).scrollPosition(for: url, mode: .rendered) == 150.5)
    }

    @Test("rendered と source モードのスクロール位置は独立して保存される")
    func modesAreIndependent() {
        let store = ScrollPositionStore(defaults: makeIsolatedDefaults(prefix: "ScrollPositionStoreTests"))
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        store.setScrollPosition(100, for: url, mode: .rendered)
        store.setScrollPosition(250, for: url, mode: .source)

        #expect(store.scrollPosition(for: url, mode: .rendered) == 100)
        #expect(store.scrollPosition(for: url, mode: .source) == 250)
    }

    @Test("ファイルごとのスクロール位置は独立している")
    func positionsAreIndependentPerFile() {
        let store = ScrollPositionStore(defaults: makeIsolatedDefaults(prefix: "ScrollPositionStoreTests"))
        let first = URL(fileURLWithPath: "/tmp/first.mmd")
        let second = URL(fileURLWithPath: "/tmp/second.md")

        store.setScrollPosition(100, for: first, mode: .rendered)
        store.setScrollPosition(200, for: second, mode: .rendered)

        #expect(store.scrollPosition(for: first, mode: .rendered) == 100)
        #expect(store.scrollPosition(for: second, mode: .rendered) == 200)
    }

    @Test("rename で旧パスのスクロール位置が新パスへ引き継がれ旧キーは消える")
    func migrateMovesValueToNewKey() {
        let store = ScrollPositionStore(defaults: makeIsolatedDefaults(prefix: "ScrollPositionStoreTests"))
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        store.setScrollPosition(300, for: old, mode: .rendered)
        store.setScrollPosition(150, for: old, mode: .source)

        store.migrateScrollPosition(from: old, to: new)

        #expect(store.scrollPosition(for: new, mode: .rendered) == 300)
        #expect(store.scrollPosition(for: new, mode: .source) == 150)
        #expect(store.scrollPosition(for: old, mode: .rendered) == 0)
        #expect(store.scrollPosition(for: old, mode: .source) == 0)
    }

    @Test("保存値のないファイルの migrate は新パスに影響しない")
    func migrateWithoutSavedValueIsNoop() {
        let store = ScrollPositionStore(defaults: makeIsolatedDefaults(prefix: "ScrollPositionStoreTests"))
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        store.setScrollPosition(200, for: new, mode: .rendered)

        store.migrateScrollPosition(from: old, to: new)

        #expect(store.scrollPosition(for: new, mode: .rendered) == 200)
    }

    @Test("シンボリックリンク経由でも同一ファイルとして扱う")
    func symlinkResolvesToSamePath() throws {
        let store = ScrollPositionStore(defaults: makeIsolatedDefaults(prefix: "ScrollPositionStoreTests"))
        let tmp = try TempDir(prefix: "ScrollPositionStoreTests")
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()

        store.setScrollPosition(120, for: link, mode: .rendered)

        #expect(store.scrollPosition(for: real, mode: .rendered) == 120)
    }
}
