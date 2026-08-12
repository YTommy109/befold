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

    @Test("remove で取り除かれる。未登録のパスを渡しても他の登録は壊れない")
    func removeDropsOnlyTheGivenBookmark() {
        let store = makeStore()
        store.add(url("a.mmd"))
        store.add(url("b.md"))

        store.remove(url("a.mmd"))
        store.remove(url("never-added.md"))

        #expect(!store.isBookmarked(url("a.mmd")))
        #expect(store.bookmarkedURLs() == [url("b.md")])
    }

    @Test("removeAll は渡された分だけをまとめて取り除く")
    func removeAllDropsGivenBookmarksOnly() {
        let store = makeStore()
        store.add(url("a.mmd"))
        store.add(url("b.md"))
        store.add(url("c.md"))

        store.removeAll([url("a.mmd"), url("c.md")])

        #expect(store.bookmarkedURLs() == [url("b.md")])
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

    /// 汚染回帰ガード(TASK-175): 隔離 defaults 上のブックマーク操作一式が、本番アプリの
    /// UserDefaults.standard("BookmarkedPaths")を一切書き換えないことを保証する。
    /// BookmarkStore.init(defaults:) の既定 .standard を復活させたり、注入を書き忘れて
    /// .standard へフォールバックする経路が再発した場合にここで検知する。
    @Test("隔離 defaults 上のブックマーク操作は本番 standard の BookmarkedPaths を汚染しない")
    func isolatedBookmarkOperationsDoNotTouchProductionStandard() {
        let productionKey = "BookmarkedPaths"
        let before = UserDefaults.standard.stringArray(forKey: productionKey)

        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "ContaminationGuard"))
        store.add(url("guard-a.mmd"))
        store.toggle(url("guard-b.md"))
        store.noteRenamed(from: url("guard-a.mmd"), to: url("guard-a2.mmd"))

        let after = UserDefaults.standard.stringArray(forKey: productionKey)
        #expect(before == after)
        #expect(after?.contains(url("guard-a2.mmd").normalizedPathKey) != true)
    }
}
