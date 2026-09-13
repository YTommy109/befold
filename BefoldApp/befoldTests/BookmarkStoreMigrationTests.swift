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

    @Test("旧値あり: 全パスがルート直下・別名なしで、見えていた表示名順のまま新キーへ写り、旧キーは消える")
    func migratesLegacyPaths() {
        let defaults = makeIsolatedDefaults(prefix: "BookmarkStoreMigration.present")
        defaults.set([note.path, diagram.path], forKey: legacyKey)

        let store = BookmarkStore(defaults: defaults)

        #expect(store.library().entries == [
            BookmarkEntry(path: diagram.path), BookmarkEntry(path: note.path),
        ])
        #expect(store.library().hasManualOrder == true)
        #expect(defaults.object(forKey: legacyKey) == nil)
        #expect(defaults.data(forKey: newKey) != nil)
        // 別インスタンス(再起動相当)でも同じ値が読める = 新キーに書かれている。
        #expect(BookmarkStore(defaults: defaults).bookmarkedURLs() == [diagram, note])
    }

    // MARK: - 手動の並びへの移行(TASK-620.3。キー Bookmarks の順序に意味を持たせた)

    /// 印の無い既存データは表示名順で見えていた。読み込み直後の並びをその順に揃え、印を付けて保存する。
    @Test("並び未移行の値あり: 表示名順へ並べて印を付け、再起動後も同じ順で読める")
    func migratesUnorderedLibraryToDisplayOrder() {
        let defaults = makeIsolatedDefaults(prefix: "BookmarkStoreMigration.order.present")
        defaults.set(Data(Self.unorderedJSON.utf8), forKey: newKey)

        let store = BookmarkStore(defaults: defaults)

        #expect(store.library().entries.map(\.displayName) == ["diagram.mmd", "note.md", "Zulu"])
        #expect(store.library().hasManualOrder == true)
        #expect(BookmarkStore(defaults: defaults).library().entries.map(\.displayName)
            == ["diagram.mmd", "note.md", "Zulu"])
    }

    @Test("並び移行済み: 保存順をそのまま保ち、書き直さない")
    func keepsManualOrderOnceMigrated() throws {
        let defaults = makeIsolatedDefaults(prefix: "BookmarkStoreMigration.order.migrated")
        let seeded = BookmarkStore(defaults: defaults)
        seeded.add(note)
        seeded.add(diagram)
        let written = try #require(defaults.data(forKey: newKey))

        let store = BookmarkStore(defaults: defaults)

        #expect(store.bookmarkedURLs() == [note, diagram])
        #expect(defaults.data(forKey: newKey) == written)
    }

    /// 手動の並びを知らない版(TASK-536)が書いた形。`hasManualOrder` キーを持たない。
    private static let unorderedJSON = """
    {"folders":[],"entries":[\
    {"path":"/mock/zeta.md","folder":[],"alias":"Zulu"},\
    {"path":"/mock/docs/note.md","folder":[]},\
    {"path":"/mock/docs/diagram.mmd","folder":[]}]}
    """

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
