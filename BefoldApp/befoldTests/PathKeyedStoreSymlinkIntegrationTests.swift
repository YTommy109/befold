@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// per-file 状態ストア(Bookmark / Zoom)の
/// シンボリックリンク解決を検証するスイート。
/// これらは `resolvingSymlinksInPath` で実パスへ正規化するため、
/// 実 symlink そのものが検証対象であり InMemoryFileReader では代替できない Integration。
@Suite
@MainActor
struct PathKeyedStoreSymlinkIntegrationTests {
    @Test("BookmarkStore: シンボリックリンク経由で add しても実体パスで isBookmarked と判定される")
    func bookmarkResolvesSymlinkToRealPath() throws {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkStoreSymlinkTests"))
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
}
