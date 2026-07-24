@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct RecentDocumentsStoreTests {
    private let defaults = makeIsolatedDefaults(prefix: "RecentDocumentsStoreTests")

    private func makeStore(maximumCount: Int = 10) -> RecentDocumentsStore {
        RecentDocumentsStore(defaults: defaults, maximumCount: maximumCount)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Users/test/\(name)")
    }

    @Test("初期状態では履歴は空")
    func startsEmpty() {
        #expect(makeStore().recentURLs().isEmpty)
    }

    @Test("開いた順の逆(新しい順)で記録される")
    func noteOpenedRecordsMostRecentFirst() {
        let store = makeStore()

        store.noteOpened(url("a.mmd"))
        store.noteOpened(url("b.md"))

        #expect(store.recentURLs().map(\.lastPathComponent) == ["b.md", "a.mmd"])
    }

    @Test("既存エントリを開き直すと先頭に移動し重複しない")
    func noteOpenedMovesExistingEntryToFront() {
        let store = makeStore()

        store.noteOpened(url("a.mmd"))
        store.noteOpened(url("b.md"))
        store.noteOpened(url("a.mmd"))

        #expect(store.recentURLs().map(\.lastPathComponent) == ["a.mmd", "b.md"])
    }

    @Test("上限を超えた分は古い方から捨てられる")
    func noteOpenedDropsOldestBeyondMaximumCount() {
        let store = makeStore(maximumCount: 2)

        store.noteOpened(url("a.mmd"))
        store.noteOpened(url("b.md"))
        store.noteOpened(url("c.mmd"))

        #expect(store.recentURLs().map(\.lastPathComponent) == ["c.mmd", "b.md"])
    }

    @Test("rename すると旧パスが新パスに置き換わる")
    func noteRenamedReplacesOldPathWithNew() {
        let store = makeStore()
        store.noteOpened(url("old.mmd"))
        store.noteOpened(url("other.md"))

        store.noteRenamed(from: url("old.mmd"), to: url("new.mmd"))

        #expect(store.recentURLs().map(\.lastPathComponent) == ["new.mmd", "other.md"])
    }

    @Test("clear で履歴が全て消える")
    func clearRemovesAllEntries() {
        let store = makeStore()
        store.noteOpened(url("a.mmd"))

        store.clear()

        #expect(store.recentURLs().isEmpty)
    }

    @Test("初回のみシステム履歴から移行し、以降の seed は無視される")
    func seedIfNeededImportsURLsOnlyOnce() {
        let store = makeStore()

        store.seedIfNeeded(with: [url("a.mmd"), url("b.md")])
        store.seedIfNeeded(with: [url("c.mmd")])

        #expect(store.recentURLs().map(\.lastPathComponent) == ["a.mmd", "b.md"])
    }

    @Test("Clear Menu 後の seed は履歴を復活させない")
    func seedIfNeededDoesNotReviveAfterClear() {
        let store = makeStore()
        store.noteOpened(url("a.mmd"))
        store.clear()

        store.seedIfNeeded(with: [url("a.mmd")])

        #expect(store.recentURLs().isEmpty)
    }

    @Test("別インスタンス(再起動相当)でも履歴が読める")
    func historyPersistsAcrossStoreInstances() {
        makeStore().noteOpened(url("a.mmd"))

        let relaunched = makeStore()

        #expect(relaunched.recentURLs().map(\.lastPathComponent) == ["a.mmd"])
    }
}
