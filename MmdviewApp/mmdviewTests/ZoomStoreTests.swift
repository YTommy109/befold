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

    @Test("範囲外の保存値は読み取り時に 0.5〜2.0 に丸められる")
    func outOfRangeZoomIsClampedOnRead() {
        let defaults = makeDefaults()
        let tooBig = URL(fileURLWithPath: "/tmp/big.mmd")
        let tooSmall = URL(fileURLWithPath: "/tmp/small.mmd")
        let store = ZoomStore(defaults: defaults)

        store.setZoom(5.0, for: tooBig)
        store.setZoom(0.1, for: tooSmall)

        #expect(store.zoom(for: tooBig) == 2.0)
        #expect(store.zoom(for: tooSmall) == 0.5)
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
