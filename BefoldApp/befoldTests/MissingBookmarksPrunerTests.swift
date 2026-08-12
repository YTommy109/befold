@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 開けなくなったブックマークの一括除去。
/// 「ユーザーが承認したものだけを消す」「承認が無ければ 1 件も消さない」を固定する。
@Suite
@MainActor
struct MissingBookmarksPrunerTests {
    private let existing = URL(fileURLWithPath: "/repo/alive.md")
    private let missing = URL(fileURLWithPath: "/deleted-worktree/gone.md")

    private func makeStore(_ urls: [URL], prefix: String) -> BookmarkStore {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: prefix))
        urls.forEach { store.add($0) }
        return store
    }

    private func makeFileReader() -> InMemoryFileReader {
        InMemoryFileReader(files: [existing.path: "# alive"])
    }

    @Test("存在しないブックマークだけを欠落として拾う")
    func detectsOnlyMissingURLs() {
        let detected = MissingBookmarksPruner.missingURLs(
            among: [existing, missing], fileReader: makeFileReader()
        )

        #expect(detected == [missing])
    }

    @Test("承認すると欠落したブックマークだけが永続化から消える")
    func removesMissingBookmarksWhenConfirmed() async {
        let store = makeStore([existing, missing], prefix: "PrunerConfirmed")
        var confirmed: [URL] = []
        let pruner = MissingBookmarksPruner(
            bookmarkStore: store, fileReader: makeFileReader(),
            confirmRemoval: { confirmed = $0; return true }, reportNoneMissing: {}
        )

        await pruner.pruneMissingBookmarks()

        #expect(confirmed == [missing])
        #expect(store.bookmarkedURLs() == [existing])
    }

    @Test("承認しなければ 1 件も消さない")
    func keepsBookmarksWhenNotConfirmed() async {
        let store = makeStore([existing, missing], prefix: "PrunerDeclined")
        let pruner = MissingBookmarksPruner(
            bookmarkStore: store, fileReader: makeFileReader(),
            confirmRemoval: { _ in false }, reportNoneMissing: {}
        )

        await pruner.pruneMissingBookmarks()

        #expect(store.bookmarkedURLs() == [existing, missing])
    }

    /// 「押しても何も起きない」と区別できないと、ユーザーは壊れていると受け取る。
    @Test("欠落が無ければ確認を出さず、その旨を伝える")
    func reportsWhenNothingIsMissing() async {
        let store = makeStore([existing], prefix: "PrunerNoneMissing")
        var confirmations = 0
        var reports = 0
        let pruner = MissingBookmarksPruner(
            bookmarkStore: store, fileReader: makeFileReader(),
            confirmRemoval: { _ in confirmations += 1; return true },
            reportNoneMissing: { reports += 1 }
        )

        await pruner.pruneMissingBookmarks()

        #expect(confirmations == 0)
        #expect(reports == 1)
        #expect(store.bookmarkedURLs() == [existing])
    }

    /// 承認は「そのとき提示した URL」に対して与えられている。承認後に欠落集合を取り直すと、
    /// 提示していないものを巻き添えで消しうる。
    @Test("承認後に増えたブックマークは、欠落していても巻き添えで消えない")
    func removesOnlyTheURLsPresentedForConfirmation() async {
        let store = makeStore([missing], prefix: "PrunerPresentedOnly")
        let later = URL(fileURLWithPath: "/deleted-worktree/added-later.md")
        let pruner = MissingBookmarksPruner(
            bookmarkStore: store, fileReader: makeFileReader(),
            confirmRemoval: { _ in
                store.add(later)
                return true
            },
            reportNoneMissing: {}
        )

        await pruner.pruneMissingBookmarks()

        #expect(store.bookmarkedURLs() == [later])
    }
}
