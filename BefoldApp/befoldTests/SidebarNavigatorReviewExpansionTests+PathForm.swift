@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// `SidebarNavigatorReviewExpansionTests` の続き(本体が type_body_length を超えるため分割)。
/// 自動展開が券に載せる URL のパス形(TASK-651)。
extension SidebarNavigatorReviewExpansionTests {
    /// 券の URL を symlink 解決済みの pathKey から作ると、配下の行が実体パスの形になり、
    /// 開いたままのパス形を基準にした相対パスが絶対パスへ落ちる(TASK-651)。
    @Test("symlink 経由で開いたディレクトリの自動展開でも、配下の行は開いたままのパス形になる")
    func revealKeepsListingPathForm() async throws {
        let tmp = try TempDir(base: Self.home)
        defer { withExtendedLifetime(tmp) {} }
        let real = tmp.url.appendingPathComponent("real")
        try FileManager.default.createDirectory(
            at: real.appendingPathComponent("a"), withIntermediateDirectories: true
        )
        // pathKey は実在するパスでしか symlink を解決しないので、変更ファイルを実際に置く。
        try Data().write(to: real.appendingPathComponent("a/x.md"))
        let link = tmp.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let fixture = makeFixture(
            "symlink", layoutMode: .tree, changedFilesOnly: false, changedFiles: ["a/x.md"], base: link
        )
        defer { withExtendedLifetime(fixture.host) {} }
        #expect(fixture.key("a/x.md").hasPrefix(real.resolvingSymlinksInPath().path))

        fixture.navigator.refreshFileList()
        await settle(fixture.navigator)
        fixture.navigator.applyDisplayChange(.toggleChangedFilesOnly)
        await settle(fixture.navigator)

        let child = try #require(fixture.navigator.fileListModel.entries.first { $0.url.lastPathComponent == "x.md" })
        #expect(child.url.path == link.appendingPathComponent("a/x.md").path)
        #expect(PathRelativizer.relativePath(of: child.url, relativeTo: link) == "a/x.md")
    }
}
