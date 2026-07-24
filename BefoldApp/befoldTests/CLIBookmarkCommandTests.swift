@testable import befold
@testable import BefoldCLI
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct CLIBookmarkCommandTests {
    private func makeStore() -> BookmarkStore {
        BookmarkStore(defaults: makeIsolatedDefaults(prefix: "CLIBookmarkCommandTests"))
    }

    @Test("存在するパスをブックマークに追加する")
    func addBookmarksExistingPath() {
        let store = makeStore()

        let result = CLIBookmarkCommand.run(
            "/tmp/diagram.mmd", addBookmark: { store.add($0) }, fileExists: { _ in true }
        )

        #expect(result.exitCode == 0)
        #expect(store.isBookmarked(URL(fileURLWithPath: "/tmp/diagram.mmd")))
    }

    @Test("同じパスを二度追加しても冪等に成功する")
    func addIsIdempotentAcrossInvocations() {
        let store = makeStore()

        _ = CLIBookmarkCommand.run("/tmp/diagram.mmd", addBookmark: { store.add($0) }, fileExists: { _ in true })
        let second = CLIBookmarkCommand.run(
            "/tmp/diagram.mmd", addBookmark: { store.add($0) }, fileExists: { _ in true }
        )

        #expect(second.exitCode == 0)
        #expect(store.bookmarkedURLs().count == 1)
    }

    @Test("存在しないパスはエラーになりブックマークされない")
    func addFailsForMissingPath() {
        let store = makeStore()

        let result = CLIBookmarkCommand.run(
            "/tmp/missing.mmd", addBookmark: { store.add($0) }, fileExists: { _ in false }
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/missing.mmd"))
        #expect(!store.isBookmarked(URL(fileURLWithPath: "/tmp/missing.mmd")))
    }
}
