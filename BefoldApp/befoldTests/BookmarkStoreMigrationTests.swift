import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 旧キー `BookmarkedPaths`(正規化パスの配列)から新キー `Bookmarks`(JSON の `BookmarkLibrary`)への
/// 一度きり移行(CLAUDE.md「UserDefaults キーの廃止・改名」の 3 ケース)。
///
/// 移行は `BookmarkStore.init` に閉じているので、観測はストアを作って `library()` と defaults の
/// キーを見る形で行う。
@Suite
@MainActor
struct BookmarkStoreMigrationTests {
    private let legacyKey = "BookmarkedPaths"
    private let newKey = "Bookmarks"
    private let note = URL(fileURLWithPath: "/mock/docs/note.md")
    private let diagram = URL(fileURLWithPath: "/mock/docs/diagram.mmd")

    @Test("旧値あり: 全パスがルート直下・別名なしで新キーへ写り、旧キーは消える")
    func migratesLegacyPaths() {
        let defaults = makeIsolatedDefaults(prefix: "BookmarkStoreMigration.present")
        defaults.set([note.path, diagram.path], forKey: legacyKey)

        let store = BookmarkStore(defaults: defaults)

        #expect(store.library().entries == [
            BookmarkEntry(path: note.path), BookmarkEntry(path: diagram.path),
        ])
        #expect(defaults.object(forKey: legacyKey) == nil)
        #expect(defaults.data(forKey: newKey) != nil)
        // 別インスタンス(再起動相当)でも同じ値が読める = 新キーに書かれている。
        #expect(BookmarkStore(defaults: defaults).bookmarkedURLs() == [note, diagram])
    }

    @Test("旧値なし: 何も書かず、既定(空)のまま")
    func leavesDefaultsUntouchedWithoutLegacyValue() {
        let defaults = makeIsolatedDefaults(prefix: "BookmarkStoreMigration.absent")
        defaults.set([note.path], forKey: "RecentDocumentPaths")

        let store = BookmarkStore(defaults: defaults)

        #expect(store.library() == BookmarkLibrary())
        #expect(defaults.data(forKey: newKey) == nil)
        #expect(defaults.object(forKey: legacyKey) == nil)
        #expect(defaults.stringArray(forKey: "RecentDocumentPaths") == [note.path])
    }

    /// 新キーがあれば旧値は写さない(以後は新キーだけが真実の源)。ただし stale な旧キーは消す。
    @Test("移行済み: 新キーの値を保ち、残っていた旧キーだけを消す")
    func skipsMigrationButRemovesStaleLegacyKey() {
        let defaults = makeIsolatedDefaults(prefix: "BookmarkStoreMigration.migrated")
        let seeded = BookmarkStore(defaults: defaults)
        seeded.add(diagram)
        seeded.setAlias("Kept", for: diagram)
        defaults.set([note.path], forKey: legacyKey)

        let store = BookmarkStore(defaults: defaults)

        #expect(store.library().entries == [BookmarkEntry(path: diagram.path, alias: "Kept")])
        #expect(!store.isBookmarked(note))
        #expect(defaults.object(forKey: legacyKey) == nil)
    }
}
