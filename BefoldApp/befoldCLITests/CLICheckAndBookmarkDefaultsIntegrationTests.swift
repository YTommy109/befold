import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// CLICheckCommand.run / CLIBookmarkCommand.run を、GUI と共通の BefoldKit 実装
/// (SupportedFileResolver)を使った既定の解決経路で検証する。
/// 実ディレクトリ列挙・実 symlink の存在確認が結果を左右するため Integration。
@Suite
struct CLICheckAndBookmarkDefaultsIntegrationTests {
    @Test("--check はフォルダー内に対応形式・非対応形式が混在していても対応形式を優先して解決する")
    func checkPrefersSupportedFormatInMixedDirectory() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.txt", contents: "plain")
        _ = try tmp.file(named: "b.md", contents: "# hi")

        let result = await CLICheckCommand.run(tmp.url.path)

        #expect(result.exitCode == 0)
        #expect(result.message.contains("b.md"))
    }

    /// 実パスへの正規化は BookmarkStore の責務で、PerFileStateStoreSymlinkIntegrationTests が
    /// 単独で検証している。ここで固定するのは CLI 側の責務、すなわち
    /// 「与えられたパスを解決せずそのまま addBookmark へ渡し、成功なら exit 0 を返す」こと。
    /// CLI が先回りして解決すると正規化規則が 2 箇所に分かれ、食い違う余地が生まれる。
    @Test("--bookmark は与えられたパスを解決せずそのまま渡し、成功なら exit 0 を返す")
    @MainActor
    func bookmarkForwardsGivenPathVerbatim() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let (_, link) = try tmp.symlinkedFile()
        var forwarded: [URL] = []

        let result = await CLIBookmarkCommand.run(link.path, addBookmark: {
            forwarded.append($0)
            return true
        })

        #expect(result.exitCode == 0)
        #expect(forwarded == [link])
    }
}
