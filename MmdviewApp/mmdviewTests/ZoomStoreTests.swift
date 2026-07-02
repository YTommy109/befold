import Foundation
import Testing
@testable import mmdview

@Suite
@MainActor
struct ZoomStoreTests {
    /// テストごとに独立した UserDefaults スイートを用意する。
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ZoomStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func zoomIsDefaultWhenUnsaved() {
        let store = ZoomStore(defaults: makeDefaults())

        #expect(store.zoom(for: URL(fileURLWithPath: "/tmp/diagram.mmd")) == 1.0)
    }

    @Test
    func setZoomPersistsPerFileAcrossInstances() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        ZoomStore(defaults: defaults).setZoom(1.5, for: url)

        #expect(ZoomStore(defaults: defaults).zoom(for: url) == 1.5)
    }

    @Test
    func zoomsAreIndependentPerFile() {
        let defaults = makeDefaults()
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
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let store = ZoomStore(defaults: defaults)

        store.setZoom(saved, for: url)

        #expect(store.zoom(for: url) == expected)
    }

    @Test("シンボリックリンク経由でも同一ファイルとして扱う")
    func symlinkResolvesToSamePath() throws {
        let defaults = makeDefaults()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZoomStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.mmd")
        try Data().write(to: real)
        let link = dir.appendingPathComponent("link.mmd")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = ZoomStore(defaults: defaults)

        store.setZoom(1.25, for: link)

        #expect(store.zoom(for: real) == 1.25)
    }
}
