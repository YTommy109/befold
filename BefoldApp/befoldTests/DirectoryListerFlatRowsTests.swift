@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 行の組み立てを SidebarRowBuilder へ一本化したあとも、**本番の入口**である
/// DirectoryLister.listEntries の出力が従来どおりであることの回帰テスト(TASK-361.1)。
///
/// SidebarRowBuilder 単体のテストでは足りない。あちらは builder の入出力を突き合わせる
/// だけなので、buildEntries の分割(親移動行の切り出し・並べ替えの適用範囲)を壊しても
/// 通ってしまう。特に `.alphabetical` は親移動行をマージ対象に含めない分岐があり、
/// 分離を誤ると `..` がファイル名としてソートに混ざる。
@Suite
struct DirectoryListerFlatRowsTests {
    /// `home` に一時ディレクトリ自身を渡すと、その親はホーム外になり親移動行が出ない。
    /// 親移動行を出したい場合は一時ディレクトリの親を `home` にする。
    private func makeFixture() throws -> (tmp: TempDir, dir: URL) {
        let tmp = try TempDir()
        let dir = tmp.url.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("mid"), withIntermediateDirectories: true
        )
        try Data().write(to: dir.appendingPathComponent("alpha.mmd"))
        try Data().write(to: dir.appendingPathComponent("zeta.mmd"))
        return (tmp, dir)
    }

    @Test("foldersFirst: 親移動行が先頭 1 件、以降はフォルダ→ファイルの順で全行 depth 0")
    func foldersFirstKeepsOrderAndZeroDepth() throws {
        let (tmp, dir) = try makeFixture()
        defer { withExtendedLifetime(tmp) {} }

        let entries = DirectoryLister.listEntryRows(in: dir, sortOrder: .foldersFirst, home: tmp.url)

        #expect(entries.map(\.kind) == [.parentNavigation, .folder, .file, .file])
        #expect(entries.first?.url.lastPathComponent == tmp.url.lastPathComponent)
        #expect(entries.dropFirst().map(\.url.lastPathComponent) == ["mid", "alpha.mmd", "zeta.mmd"])
        #expect(entries.allSatisfy { $0.depth == 0 })
    }

    /// `..` は上位フォルダーへの移動手段であって一覧の項目ではないため、名前順の
    /// マージへ混ぜてはならない。混ざると `alpha.mmd` より後ろへ落ちる。
    @Test("alphabetical: 親移動行はソートに混ざらず先頭に残り、以降だけが名前順になる")
    func alphabeticalKeepsParentNavigationFirst() throws {
        let (tmp, dir) = try makeFixture()
        defer { withExtendedLifetime(tmp) {} }

        let entries = DirectoryLister.listEntryRows(in: dir, sortOrder: .alphabetical, home: tmp.url)

        #expect(entries.first?.kind == .parentNavigation)
        #expect(entries.first?.url.lastPathComponent == tmp.url.lastPathComponent)
        #expect(entries.dropFirst().map(\.url.lastPathComponent) == ["alpha.mmd", "mid", "zeta.mmd"])
        #expect(entries.allSatisfy { $0.depth == 0 })
    }

    @Test("ホームの外へは親移動行を出さない(従来どおり)")
    func omitsParentNavigationOutsideHome() throws {
        let (tmp, dir) = try makeFixture()
        defer { withExtendedLifetime(tmp) {} }

        let entries = DirectoryLister.listEntryRows(in: dir, sortOrder: .foldersFirst, home: dir)

        #expect(!entries.contains { $0.kind == .parentNavigation })
        #expect(entries.allSatisfy { $0.depth == 0 })
    }
}
