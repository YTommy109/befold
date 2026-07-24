@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// per-file 状態ストア(Bookmark / Zoom / Sidebar / ScrollPosition)の
/// シンボリックリンク解決を検証するスイート。
/// これらは `resolvingSymlinksInPath` で実パスへ正規化するため、
/// 実 symlink そのものが検証対象であり InMemoryFileReader では代替できない Integration。
@Suite
@MainActor
struct PerFileStateStoreSymlinkIntegrationTests {
    @Test("BookmarkStore: シンボリックリンク経由で add しても実体パスで isBookmarked と判定される")
    func bookmarkResolvesSymlinkToRealPath() throws {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkStoreTests"))
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()

        store.add(link)

        #expect(store.isBookmarked(real))
    }

    @Test("ZoomStore: シンボリックリンク経由でも同一ファイルとして扱う")
    func zoomResolvesSymlinkToSamePath() throws {
        let store = ZoomStore(defaults: makeIsolatedDefaults(prefix: "ZoomStoreTests"))
        let tmp = try TempDir(prefix: "ZoomStoreTests")
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()

        store.setZoom(1.25, for: link)

        #expect(store.zoom(for: real) == 1.25)
    }

    @Test("SidebarStateStore: シンボリックリンク経由でも同一ファイルとして扱う")
    func sidebarResolvesSymlinkToSamePath() throws {
        let store = SidebarStateStore(defaults: makeIsolatedDefaults(prefix: "SidebarStateStoreTests"))
        let tmp = try TempDir(prefix: "SidebarStateStoreTests")
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()

        store.setCollapsed(false, for: link)

        #expect(store.isCollapsed(for: real) == false)
    }

    @Test("ScrollPositionStore: シンボリックリンク経由でも同一ファイルとして扱う")
    func scrollPositionResolvesSymlinkToSamePath() throws {
        let store = ScrollPositionStore(defaults: makeIsolatedDefaults(prefix: "ScrollPositionStoreTests"))
        let tmp = try TempDir(prefix: "ScrollPositionStoreTests")
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()

        store.setScrollPosition(120, for: link, mode: .rendered)

        #expect(store.scrollPosition(for: real, mode: .rendered) == 120)
    }
}
