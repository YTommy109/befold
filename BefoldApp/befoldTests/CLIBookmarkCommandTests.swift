@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct CLIBookmarkCommandTests {
    private func makeStore() -> BookmarkStore {
        BookmarkStore(defaults: makeIsolatedDefaults(prefix: "CLIBookmarkCommandTests"))
    }

    @Test("bookmark add <path> は存在するパスをブックマークに追加する")
    func addBookmarksExistingPath() {
        let store = makeStore()

        let result = CLIBookmarkCommand.run(
            ["add", "/tmp/diagram.mmd"], bookmarkStore: store, fileExists: { _ in true }
        )

        #expect(result.exitCode == 0)
        #expect(store.isBookmarked(URL(fileURLWithPath: "/tmp/diagram.mmd")))
    }

    @Test("同じパスを二度追加しても冪等に成功する")
    func addIsIdempotentAcrossInvocations() {
        let store = makeStore()

        _ = CLIBookmarkCommand.run(["add", "/tmp/diagram.mmd"], bookmarkStore: store, fileExists: { _ in true })
        let second = CLIBookmarkCommand.run(
            ["add", "/tmp/diagram.mmd"], bookmarkStore: store, fileExists: { _ in true }
        )

        #expect(second.exitCode == 0)
        #expect(store.bookmarkedURLs().count == 1)
    }

    @Test("存在しないパスはエラーになりブックマークされない")
    func addFailsForMissingPath() {
        let store = makeStore()

        let result = CLIBookmarkCommand.run(
            ["add", "/tmp/missing.mmd"], bookmarkStore: store, fileExists: { _ in false }
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/missing.mmd"))
        #expect(!store.isBookmarked(URL(fileURLWithPath: "/tmp/missing.mmd")))
    }

    @Test("add 以外・引数不足は usage エラーになる")
    func invalidArgumentsReturnUsageError() {
        let store = makeStore()

        #expect(CLIBookmarkCommand.run([], bookmarkStore: store).exitCode == 64)
        #expect(CLIBookmarkCommand.run(["remove", "/tmp/a.mmd"], bookmarkStore: store).exitCode == 64)
        #expect(CLIBookmarkCommand.run(["add"], bookmarkStore: store).exitCode == 64)
    }
}
