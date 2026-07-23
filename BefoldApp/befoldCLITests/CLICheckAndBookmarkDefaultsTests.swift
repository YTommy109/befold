import BefoldCLI
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// CLICheckCommand.run / CLIBookmarkCommand.run を、GUI と共通の BefoldKit 実装
/// (SupportedFileResolver・BookmarkStore)を使った既定の解決経路で検証する(TASK-110/TASK-111)。
@Suite
struct CLICheckAndBookmarkDefaultsTests {
    @Test("--check はフォルダー内に対応形式・非対応形式が混在していても対応形式を優先して解決する(TASK-110)")
    func checkPrefersSupportedFormatInMixedDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.txt", contents: "plain")
        _ = try tmp.file(named: "b.md", contents: "# hi")

        let result = CLICheckCommand.run(tmp.url.path)

        #expect(result.exitCode == 0)
        #expect(result.message.contains("b.md"))
    }

    @Test("--bookmark はシンボリックリンク経由でも実体パスで正規化して登録する(TASK-111)")
    @MainActor
    func bookmarkResolvesSymlinkToRealPath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "CLICheckAndBookmarkDefaultsTests"))

        let result = CLIBookmarkCommand.run(link.path, addBookmark: { store.add($0) })

        #expect(result.exitCode == 0)
        #expect(store.isBookmarked(real))
    }
}
