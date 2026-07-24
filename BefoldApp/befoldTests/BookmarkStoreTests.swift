@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct BookmarkStoreTests {
    private let defaults = makeIsolatedDefaults(prefix: "BookmarkStoreTests")

    private func makeStore() -> BookmarkStore {
        BookmarkStore(defaults: defaults)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Users/test/\(name)")
    }

    @Test("初期状態ではブックマークされていない")
    func startsUnbookmarked() {
        #expect(!makeStore().isBookmarked(url("a.mmd")))
    }

    @Test("add で追加され isBookmarked が true になる")
    func addAddsBookmark() {
        let store = makeStore()

        store.add(url("a.mmd"))

        #expect(store.isBookmarked(url("a.mmd")))
    }

    @Test("add を同じパスへ複数回呼んでも冪等に成功する")
    func addIsIdempotent() {
        let store = makeStore()

        store.add(url("a.mmd"))
        store.add(url("a.mmd"))

        #expect(store.isBookmarked(url("a.mmd")))
        #expect(store.bookmarkedURLs().count == 1)
    }

    @Test("toggle で追加され isBookmarked が true になる")
    func toggleAddsBookmark() {
        let store = makeStore()

        store.toggle(url("a.mmd"))

        #expect(store.isBookmarked(url("a.mmd")))
    }

    @Test("toggle を再度呼ぶと解除され isBookmarked が false になる")
    func toggleRemovesExistingBookmark() {
        let store = makeStore()
        store.toggle(url("a.mmd"))

        store.toggle(url("a.mmd"))

        #expect(!store.isBookmarked(url("a.mmd")))
    }

    @Test("bookmarkedURLs がブックマーク済み URL を返す")
    func bookmarkedURLsReturnsBookmarkedEntries() {
        let store = makeStore()
        store.toggle(url("a.mmd"))
        store.toggle(url("b.md"))

        #expect(Set(store.bookmarkedURLs().map(\.lastPathComponent)) == ["a.mmd", "b.md"])
    }

    @Test("rename するとブックマーク済みキーが新パスに引き継がれる")
    func noteRenamedCarriesOverBookmarkedKey() {
        let store = makeStore()
        store.toggle(url("old.mmd"))

        store.noteRenamed(from: url("old.mmd"), to: url("new.mmd"))

        #expect(store.isBookmarked(url("new.mmd")))
        #expect(!store.isBookmarked(url("old.mmd")))
    }

    @Test("ブックマークされていないファイルの rename は何もしない")
    func noteRenamedIgnoresUnbookmarkedFile() {
        let store = makeStore()

        store.noteRenamed(from: url("old.mmd"), to: url("new.mmd"))

        #expect(!store.isBookmarked(url("new.mmd")))
        #expect(store.bookmarkedURLs().isEmpty)
    }

    @Test("別インスタンス(再起動相当)でもブックマークが読める")
    func bookmarksPersistAcrossStoreInstances() {
        makeStore().toggle(url("a.mmd"))

        let relaunched = makeStore()

        #expect(relaunched.isBookmarked(url("a.mmd")))
    }

    @Test("シンボリックリンク経由で add しても実体パスで isBookmarked と判定される")
    func addResolvesSymlinkToRealPath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()
        let store = makeStore()

        store.add(link)

        #expect(store.isBookmarked(real))
    }
}
