@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// pruneMissing が「変更が無ければ書き込まない」ことを検証するための、
/// 書き込み回数を数える UserDefaults ラッパー。makeIsolatedDefaults(InMemoryUserDefaults)と
/// 同じくディスクに触れない実装(プリミティブを上書き)にした上で書き込み回数だけ記録する。
private final class WriteCountingUserDefaults: UserDefaults {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    private(set) var writeCount = 0

    override func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        writeCount += 1
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: defaultName)
    }
}

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

    @Test("record は渡された mainRoot を保存する")
    func recordStoresMainRoot() {
        let store = makeStore()

        store.record(root: url("repoA-wt"), label: "repoA-wt", mainRoot: url("repoA"))

        #expect(store.entries().first?.mainRootPath == url("repoA").normalizedPathKey)
    }

    @Test("record は mainRoot 未指定なら既存の mainRootPath を保持する")
    func recordPreservesExistingMainRootWhenNotGiven() {
        let store = makeStore()
        store.record(root: url("repoA-wt"), label: "repoA-wt", mainRoot: url("repoA"))

        store.record(root: url("repoA-wt"), label: "repoA-wt")

        #expect(store.entries().first?.mainRootPath == url("repoA").normalizedPathKey)
    }

    @Test("record は新しい mainRoot が渡されたら既存値を更新する")
    func recordUpdatesMainRootWhenGiven() {
        let store = makeStore()
        store.record(root: url("repoA-wt"), label: "repoA-wt", mainRoot: url("repoA"))

        store.record(root: url("repoA-wt"), label: "repoA-wt", mainRoot: url("repoZ"))

        #expect(store.entries().first?.mainRootPath == url("repoZ").normalizedPathKey)
    }

    @Test("mainRootPath を持たない旧データもデコードでき nil になる")
    func decodesLegacyEntryWithoutMainRootPath() {
        let legacy = Data(#"[{"rootPath":"/Users/test/repoA","label":"repoA"}]"#.utf8)
        defaults.set(legacy, forKey: "RecentRepositories")

        let entries = makeStore().entries()

        #expect(entries.map(\.label) == ["repoA"])
        #expect(entries.first?.mainRootPath == nil)
    }

    @Test("groupKey は mainRootPath があればそれを、無ければ rootPath を正規化して返す")
    func groupKeyFallsBackToRootPath() {
        let grouped = RecentRepositoryEntry(
            rootPath: "/Users/test/repoA-wt", label: "wt", lastTabGroup: nil,
            mainRootPath: "/Users/test/repoA"
        )
        let standalone = RecentRepositoryEntry(
            rootPath: "/Users/test/repoA", label: "repoA", lastTabGroup: nil, mainRootPath: nil
        )

        #expect(grouped.groupKey == url("repoA").normalizedPathKey)
        #expect(standalone.groupKey == url("repoA").normalizedPathKey)
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

    /// 「repoA に paths のタブ構成が保存されている」状態を作る。
    private func makeStoreWithTabGroup(paths: [String]) -> RecentRepositoriesStore {
        let store = makeStore()
        store.record(root: url("repoA"), label: "repoA")
        store.updateLastTabGroup(
            root: url("repoA"), SessionLayout.TabGroup(paths: paths, selectedPath: paths.first)
        )
        return store
    }

    @Test("保存済みタブ構成の真部分集合への縮小は拒否する")
    func updateLastTabGroupRefusesStrictSubset() {
        let store = makeStoreWithTabGroup(paths: ["/a", "/b"])

        store.updateLastTabGroup(root: url("repoA"), SessionLayout.TabGroup(paths: ["/b"], selectedPath: "/b"))

        #expect(store.entries().first?.lastTabGroup?.paths == ["/a", "/b"])
    }

    @Test("同じパス集合なら選択タブの変更が書き込まれる")
    func updateLastTabGroupWritesWhenPathsAreUnchanged() {
        let store = makeStoreWithTabGroup(paths: ["/a", "/b"])

        store.updateLastTabGroup(
            root: url("repoA"), SessionLayout.TabGroup(paths: ["/a", "/b"], selectedPath: "/b")
        )

        #expect(store.entries().first?.lastTabGroup?.selectedPath == "/b")
    }

    @Test("新しいパスを含むタブ構成は書き込まれる")
    func updateLastTabGroupWritesWhenPathsAreAdded() {
        let store = makeStoreWithTabGroup(paths: ["/a", "/b"])

        store.updateLastTabGroup(
            root: url("repoA"), SessionLayout.TabGroup(paths: ["/b", "/c"], selectedPath: "/c")
        )

        #expect(store.entries().first?.lastTabGroup?.paths == ["/b", "/c"])
    }

    @Test("force 付きなら真部分集合でも書き込まれる")
    func updateLastTabGroupForceOverridesRefusal() {
        let store = makeStoreWithTabGroup(paths: ["/a", "/b"])

        store.updateLastTabGroup(
            root: url("repoA"), SessionLayout.TabGroup(paths: ["/b"], selectedPath: "/b"), force: true
        )

        #expect(store.entries().first?.lastTabGroup?.paths == ["/b"])
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

    /// pruneMissing が見るのは fileReader.isDirectory だけなので、実ファイルシステムは
    /// 検証価値を持たない。存在するディレクトリだけを持つインメモリ実装で置き換える。
    private func makeStore(
        defaults: UserDefaults? = nil, existingDirectories: [URL]
    ) -> RecentRepositoriesStore {
        RecentRepositoriesStore(
            defaults: defaults ?? self.defaults,
            fileReader: InMemoryFileReader(
                directories: Set(existingDirectories.map(\.normalizedPathKey))
            )
        )
    }

    @Test("pruneMissingAsync は存在しないルートを取り除く")
    func pruneMissingRemovesNonExistentRoots() async {
        let present = url("present")
        let missing = url("present/gone")
        let store = makeStore(existingDirectories: [present])
        store.record(root: present, label: "kept")
        store.record(root: missing, label: "gone")

        await store.pruneMissingAsync()

        #expect(store.entries().map(\.label) == ["kept"])
    }

    @Test("pruneMissingAsync はデコード不能な保存データを空リストで上書きしない")
    func pruneMissingLeavesCorruptedDataUntouched() async {
        let store = makeStore()
        let corrupted = Data("not valid json".utf8)
        defaults.set(corrupted, forKey: "RecentRepositories")

        await store.pruneMissingAsync()

        #expect(defaults.data(forKey: "RecentRepositories") == corrupted)
    }

    @Test("pruneMissingAsync は取り除く対象が無ければ defaults へ書き込まない")
    func pruneMissingSkipsWriteWhenNothingIsMissing() async {
        let present = url("present")
        let spyDefaults = WriteCountingUserDefaults()
        let store = makeStore(defaults: spyDefaults, existingDirectories: [present])
        store.record(root: present, label: "kept")
        let writesAfterRecord = spyDefaults.writeCount

        await store.pruneMissingAsync()

        #expect(spyDefaults.writeCount == writesAfterRecord)
    }
}
