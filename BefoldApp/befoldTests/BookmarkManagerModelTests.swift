@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 管理パネルのモデル。ストアへの書き込みと、集合が変わったときだけ `onChange` が呼ばれることを固定する。
@Suite
@MainActor
struct BookmarkManagerModelTests {
    private let note = URL(fileURLWithPath: "/mock/docs/note.md")
    private let diagram = URL(fileURLWithPath: "/mock/docs/diagram.mmd")

    private func makeStore() -> BookmarkStore {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkManagerModelTests"))
        store.add(note)
        store.add(diagram)
        return store
    }

    @Test("remove でストアから消え、一覧が更新され、onChange が 1 回呼ばれる")
    func removeWritesThroughAndNotifiesOnce() {
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: { changes += 1 })

        model.remove(note)

        #expect(!store.isBookmarked(note))
        #expect(store.isBookmarked(diagram))
        #expect(model.entries.map(\.url) == [diagram])
        #expect(changes == 1)
    }

    /// 未登録のパスは書き込みも通知も起こさない(窓のツールバーを無駄に再同期しない)。
    @Test("未登録のパスの remove は何もせず onChange も呼ばない")
    func removeIgnoresUnknownPath() {
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: { changes += 1 })

        model.remove(URL(fileURLWithPath: "/mock/unknown.md"))

        #expect(store.bookmarkedURLs() == [note, diagram])
        #expect(changes == 0)
    }

    /// 別名は集合を変えないので窓側に伝える必要が無い。
    @Test("setAlias は一覧に反映されるが onChange は呼ばない")
    func setAliasRefreshesWithoutNotifying() {
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: { changes += 1 })

        model.setAlias("Zulu", for: note)

        #expect(model.entries.map(\.displayName) == ["diagram.mmd", "Zulu"])
        #expect(changes == 0)
    }

    /// パネルの外(窓の ⌘D・欠落の一括削除)で変わった分は refresh で拾う。
    @Test("refresh はストアの現在値を取り直す")
    func refreshPicksUpExternalChanges() {
        let store = makeStore()
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: {})
        store.remove(diagram)

        model.refresh()

        #expect(model.entries.map(\.url) == [note])
    }
}
