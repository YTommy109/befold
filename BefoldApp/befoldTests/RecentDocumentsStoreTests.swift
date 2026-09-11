@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// システム管理の履歴(`NSDocumentController`)への通知を観測するための差し替え先。
/// 本物を呼ぶとテスト実行側の「最近使った項目」を書き換えてしまうため、ここで受ける。
@MainActor
private final class SystemRecentSpy {
    private(set) var urls: [URL] = []

    func note(_ url: URL) {
        urls.append(url)
    }
}

@Suite
@MainActor
struct RecentDocumentsStoreTests {
    private let defaults = makeIsolatedDefaults(prefix: "RecentDocumentsStoreTests")

    private func makeStore(
        maximumCount: Int = 10, spy: SystemRecentSpy = SystemRecentSpy()
    ) -> RecentDocumentsStore {
        RecentDocumentsStore(
            defaults: defaults, maximumCount: maximumCount, noteSystemRecent: { spy.note($0) }
        )
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

        store.noteOpened(url("a.mmd"), kind: .viewer)
        store.noteOpened(url("b.md"), kind: .viewer)

        #expect(store.recentURLs().map(\.lastPathComponent) == ["b.md", "a.mmd"])
    }

    @Test("既存エントリを開き直すと先頭に移動し重複しない")
    func noteOpenedMovesExistingEntryToFront() {
        let store = makeStore()

        store.noteOpened(url("a.mmd"), kind: .viewer)
        store.noteOpened(url("b.md"), kind: .viewer)
        store.noteOpened(url("a.mmd"), kind: .viewer)

        #expect(store.recentURLs().map(\.lastPathComponent) == ["a.mmd", "b.md"])
    }

    @Test("上限を超えた分は古い方から捨てられる")
    func noteOpenedDropsOldestBeyondMaximumCount() {
        let store = makeStore(maximumCount: 2)

        store.noteOpened(url("a.mmd"), kind: .viewer)
        store.noteOpened(url("b.md"), kind: .viewer)
        store.noteOpened(url("c.mmd"), kind: .viewer)

        #expect(store.recentURLs().map(\.lastPathComponent) == ["c.mmd", "b.md"])
    }

    /// 既定の上限はメニューに並ぶ件数そのものなので、変更したらここが落ちる。
    @Test("既定の上限は 25 件")
    func defaultMaximumCountIs25() {
        let store = RecentDocumentsStore(defaults: defaults, noteSystemRecent: { _ in })

        for index in 0 ..< 26 {
            store.noteOpened(url("file\(index).md"), kind: .viewer)
        }

        #expect(store.recentURLs().count == 25)
        #expect(store.recentURLs().first?.lastPathComponent == "file25.md")
        #expect(store.recentURLs().last?.lastPathComponent == "file1.md")
    }

    @Test("rename すると旧パスが新パスに置き換わる")
    func noteRenamedReplacesOldPathWithNew() {
        let store = makeStore()
        store.noteOpened(url("old.mmd"), kind: .viewer)
        store.noteOpened(url("other.md"), kind: .viewer)

        store.noteRenamed(from: url("old.mmd"), to: url("new.mmd"), kind: .viewer)

        #expect(store.recentURLs().map(\.lastPathComponent) == ["new.mmd", "other.md"])
    }

    @Test("スライド窓で開いても自前の履歴にもシステムの履歴にも積まれない")
    func noteOpenedSkipsSlideKind() {
        let spy = SystemRecentSpy()
        let store = makeStore(spy: spy)

        store.noteOpened(url("a.mmd"), kind: .viewer)
        store.noteOpened(url("slide.md"), kind: .slide)

        #expect(store.recentURLs().map(\.lastPathComponent) == ["a.mmd"])
        #expect(spy.urls.map(\.lastPathComponent) == ["a.mmd"])
    }

    /// 積まないだけで、既に載っている項目が消えたパスを指したまま残るのは避ける。
    @Test("スライド窓の rename は先頭へ昇格させず、位置を保って置き換える")
    func noteRenamedFromSlideKeepsPositionWithoutPromoting() {
        let spy = SystemRecentSpy()
        let store = makeStore(spy: spy)
        store.noteOpened(url("old.mmd"), kind: .viewer)
        store.noteOpened(url("other.md"), kind: .viewer)

        store.noteRenamed(from: url("old.mmd"), to: url("new.mmd"), kind: .slide)

        #expect(store.recentURLs().map(\.lastPathComponent) == ["other.md", "new.mmd"])
        #expect(spy.urls.map(\.lastPathComponent) == ["old.mmd", "other.md"])
    }

    /// 通常窓の rename は `moveToFront` が重複を潰していたが、スライド窓の置き換えは
    /// `replace` だけを通る。そこで潰さないと同じパスが 2 回並ぶ(レビュー指摘の回帰)。
    @Test("スライド窓で履歴にあるパスへ rename しても、そのパスが 2 回並ばない")
    func noteRenamedFromSlideDoesNotDuplicateExistingPath() {
        let store = makeStore()
        store.noteOpened(url("a.mmd"), kind: .viewer)
        store.noteOpened(url("b.md"), kind: .viewer)

        store.noteRenamed(from: url("a.mmd"), to: url("b.md"), kind: .slide)

        #expect(store.recentURLs().map(\.lastPathComponent) == ["b.md"])
    }

    @Test("履歴に無いファイルはスライド窓で rename しても増えない")
    func noteRenamedFromSlideDoesNotAddUnlistedFile() {
        let store = makeStore()

        store.noteRenamed(from: url("old.mmd"), to: url("new.mmd"), kind: .slide)

        #expect(store.recentURLs().isEmpty)
    }

    @Test("clear で履歴が全て消える")
    func clearRemovesAllEntries() {
        let store = makeStore()
        store.noteOpened(url("a.mmd"), kind: .viewer)

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
        store.noteOpened(url("a.mmd"), kind: .viewer)
        store.clear()

        store.seedIfNeeded(with: [url("a.mmd")])

        #expect(store.recentURLs().isEmpty)
    }

    @Test("別インスタンス(再起動相当)でも履歴が読める")
    func historyPersistsAcrossStoreInstances() {
        makeStore().noteOpened(url("a.mmd"), kind: .viewer)

        let relaunched = makeStore()

        #expect(relaunched.recentURLs().map(\.lastPathComponent) == ["a.mmd"])
    }
}
