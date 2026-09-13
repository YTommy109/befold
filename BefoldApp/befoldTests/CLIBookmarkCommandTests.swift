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
    func addBookmarksExistingPath() async {
        let store = makeStore()

        let result = await CLIBookmarkCommand.run(
            "/tmp/diagram.mmd",
            addBookmark: { store.add($0); return true },
            fileReader: InMemoryFileReader(files: ["/tmp/diagram.mmd": ""])
        )

        #expect(result.exitCode == 0)
        #expect(store.isBookmarked(URL(fileURLWithPath: "/tmp/diagram.mmd")))
    }

    @Test("同じパスを二度追加しても冪等に成功する")
    func addIsIdempotentAcrossInvocations() async {
        let store = makeStore()
        let add: @MainActor (URL) -> Bool = { store.add($0); return true }
        let reader = InMemoryFileReader(files: ["/tmp/diagram.mmd": ""])

        _ = await CLIBookmarkCommand.run("/tmp/diagram.mmd", addBookmark: add, fileReader: reader)
        let second = await CLIBookmarkCommand.run("/tmp/diagram.mmd", addBookmark: add, fileReader: reader)

        #expect(second.exitCode == 0)
        #expect(store.bookmarkedURLs().count == 1)
    }

    @Test("存在しないパスはエラーになりブックマークされない")
    func addFailsForMissingPath() async {
        let store = makeStore()

        let result = await CLIBookmarkCommand.run(
            "/tmp/missing.mmd",
            addBookmark: { store.add($0); return true },
            fileReader: InMemoryFileReader()
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/missing.mmd"))
        #expect(!store.isBookmarked(URL(fileURLWithPath: "/tmp/missing.mmd")))
    }

    /// フォルダーはブックマークできない。GUI 起動中は転送先がパスを判定しないので、転送する前に弾く
    /// (`addBookmark` = 転送/追加そのものが呼ばれないこと)。TASK-621。
    @Test("フォルダーはエラーになり、追加も転送もしない")
    func addFailsForFolder() async {
        var calls = 0

        let result = await CLIBookmarkCommand.run(
            "/tmp/docs",
            addBookmark: { _ in calls += 1; return true },
            fileReader: InMemoryFileReader(directories: ["/tmp/docs"])
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/docs"))
        #expect(calls == 0)
    }

    /// 起動中インスタンスへの転送が届かなかったときに成功を報告すると、CLI は exit 0 なのに
    /// ブックマークがどこにも残らない無言失敗になる。追加の可否をそのまま結果に反映する。
    @Test("追加に失敗した場合はエラーを返す")
    func addFailureIsReported() async {
        let result = await CLIBookmarkCommand.run(
            "/tmp/diagram.mmd",
            addBookmark: { _ in false },
            fileReader: InMemoryFileReader(files: ["/tmp/diagram.mmd": ""])
        )

        #expect(result.exitCode != 0)
        #expect(result.message.contains("/tmp/diagram.mmd"))
    }
}
