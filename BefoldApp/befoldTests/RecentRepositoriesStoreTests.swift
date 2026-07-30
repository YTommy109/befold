@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct RecentRepositoriesStoreTests {
    private let defaults = makeIsolatedDefaults(prefix: "RecentRepositoriesStoreTests")

    private func makeStore(maximumCount: Int = 10) -> RecentRepositoriesStore {
        RecentRepositoriesStore(defaults: defaults, maximumCount: maximumCount)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Users/test/\(name)")
    }

    @Test("初期状態では一覧は空")
    func startsEmpty() {
        #expect(makeStore().entries().isEmpty)
    }

    @Test("記録した順の逆(新しい順)で並ぶ")
    func recordOrdersMostRecentFirst() {
        let store = makeStore()

        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")

        #expect(store.entries().map(\.label) == ["repoB", "repoA"])
    }

    @Test("既存エントリを開き直すと先頭に移動し重複しない")
    func recordMovesExistingEntryToFront() {
        let store = makeStore()

        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")
        store.record(root: url("repoA"), label: "repoA")

        #expect(store.entries().map(\.label) == ["repoA", "repoB"])
    }

    @Test("上限を超えた分は古い方から捨てられる")
    func recordDropsOldestBeyondMaximumCount() {
        let store = makeStore(maximumCount: 2)

        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")
        store.record(root: url("repoC"), label: "repoC")

        #expect(store.entries().map(\.label) == ["repoC", "repoB"])
    }

    @Test("record は既存エントリの lastTabGroup を保持する")
    func recordPreservesExistingLastTabGroup() {
        let store = makeStore()
        store.record(root: url("repoA"), label: "repoA")
        let group = SessionLayout.TabGroup(paths: [url("repoA/a.md").path], selectedPath: url("repoA/a.md").path)
        store.updateLastTabGroup(root: url("repoA"), group)

        store.record(root: url("repoA"), label: "repoA")

        #expect(store.entries().first?.lastTabGroup == group)
    }

    @Test("updateLastTabGroup は該当エントリのタブ構成のみ更新し並び順は変えない")
    func updateLastTabGroupUpdatesWithoutReordering() {
        let store = makeStore()
        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")
        let group = SessionLayout.TabGroup(paths: [url("repoA/a.md").path], selectedPath: url("repoA/a.md").path)

        store.updateLastTabGroup(root: url("repoA"), group)

        #expect(store.entries().map(\.label) == ["repoB", "repoA"])
        #expect(store.entries().first { $0.label == "repoA" }?.lastTabGroup == group)
    }

    @Test("記録されていないルートへの updateLastTabGroup は何もしない")
    func updateLastTabGroupIgnoresUnknownRoot() {
        let store = makeStore()
        let group = SessionLayout.TabGroup(paths: ["/x"], selectedPath: "/x")

        store.updateLastTabGroup(root: url("unknown"), group)

        #expect(store.entries().isEmpty)
    }

    @Test("clear で一覧が全て消える")
    func clearRemovesAllEntries() {
        let store = makeStore()
        store.record(root: url("repoA"), label: "repoA")

        store.clear()

        #expect(store.entries().isEmpty)
    }

    @Test("別インスタンス(再起動相当)でも一覧が読める")
    func entriesPersistAcrossStoreInstances() {
        makeStore().record(root: url("repoA"), label: "repoA")

        let relaunched = makeStore()

        #expect(relaunched.entries().map(\.label) == ["repoA"])
    }

    @Test("pruneMissing は存在しないルートを取り除く")
    func pruneMissingRemovesNonExistentRoots() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let missing = temp.url.appendingPathComponent("gone")
        let store = RecentRepositoriesStore(defaults: defaults, fileReader: DefaultFileReader())
        store.record(root: temp.url, label: "kept")
        store.record(root: missing, label: "gone")

        store.pruneMissing()

        #expect(store.entries().map(\.label) == ["kept"])
    }
}
