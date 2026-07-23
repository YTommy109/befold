@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct ZoomStoreTests {
    @Test
    func zoomIsDefaultWhenUnsaved() {
        let store = ZoomStore(defaults: makeIsolatedDefaults(prefix: "ZoomStoreTests"))

        #expect(store.zoom(for: URL(fileURLWithPath: "/tmp/diagram.mmd")) == 1.0)
    }

    @Test
    func setZoomPersistsPerFileAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "ZoomStoreTests")
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        ZoomStore(defaults: defaults).setZoom(1.5, for: url)

        #expect(ZoomStore(defaults: defaults).zoom(for: url) == 1.5)
    }

    @Test
    func zoomsAreIndependentPerFile() {
        let defaults = makeIsolatedDefaults(prefix: "ZoomStoreTests")
        let first = URL(fileURLWithPath: "/tmp/first.mmd")
        let second = URL(fileURLWithPath: "/tmp/second.md")
        let store = ZoomStore(defaults: defaults)

        store.setZoom(0.75, for: first)
        store.setZoom(2.0, for: second)

        #expect(store.zoom(for: first) == 0.75)
        #expect(store.zoom(for: second) == 2.0)
    }

    /// 保存値は読み取り時に 0.5〜2.0 に clamp され、境界値ちょうどはそのまま保持される。
    @Test(arguments: [
        (5.0, 2.0),
        (0.1, 0.5),
        (2.0, 2.0),
        (0.5, 0.5),
    ])
    func zoomIsClampedToRangeOnRead(saved: Double, expected: Double) {
        let defaults = makeIsolatedDefaults(prefix: "ZoomStoreTests")
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let store = ZoomStore(defaults: defaults)

        store.setZoom(saved, for: url)

        #expect(store.zoom(for: url) == expected)
    }

    @Test("rename で旧パスの倍率が新パスへ引き継がれ旧キーは消える")
    func migrateZoomMovesValueToNewKey() {
        let defaults = makeIsolatedDefaults(prefix: "ZoomStoreTests")
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = ZoomStore(defaults: defaults)
        store.setZoom(1.75, for: old)

        store.migrateZoom(from: old, to: new)

        #expect(store.zoom(for: new) == 1.75)
        // 旧キーは削除され、既定値に戻る
        #expect(store.zoom(for: old) == ZoomStore.defaultZoom)
    }

    @Test("保存値のないファイルの migrate は新パスに影響しない")
    func migrateZoomWithoutSavedValueIsNoop() {
        let defaults = makeIsolatedDefaults(prefix: "ZoomStoreTests")
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = ZoomStore(defaults: defaults)
        store.setZoom(1.5, for: new)

        store.migrateZoom(from: old, to: new)

        // 旧パスに保存値がないため、新パスの既存倍率は上書きされない
        #expect(store.zoom(for: new) == 1.5)
    }

    @Test("シンボリックリンク経由でも同一ファイルとして扱う")
    func symlinkResolvesToSamePath() throws {
        let defaults = makeIsolatedDefaults(prefix: "ZoomStoreTests")
        let tmp = try TempDir(prefix: "ZoomStoreTests")
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()
        let store = ZoomStore(defaults: defaults)

        store.setZoom(1.25, for: link)

        #expect(store.zoom(for: real) == 1.25)
    }
}
