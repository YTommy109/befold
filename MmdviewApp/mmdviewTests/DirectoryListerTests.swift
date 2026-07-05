import Foundation
@testable import mmdview
import Testing

@Suite
struct DirectoryListerTests {
    @Test("対応拡張子のファイルだけが返される")
    func listFilesFiltersByExtension() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let mmd = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let md = try tmp.file(named: "readme.md", contents: "# Hi")
        _ = try tmp.file(named: "photo.png", contents: "binary")
        _ = try tmp.file(named: "data.csv", contents: "a,b")

        let result = DirectoryLister.listFiles(in: tmp.url)

        let names = result.map(\.lastPathComponent)
        #expect(names.contains("diagram.mmd"))
        #expect(names.contains("readme.md"))
        #expect(!names.contains("photo.png"))
        #expect(!names.contains("data.csv"))
    }

    @Test("結果がファイル名でローカライズソートされる")
    func listFilesSortsByName() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "c.mmd", contents: "")
        _ = try tmp.file(named: "a.mmd", contents: "")
        _ = try tmp.file(named: "b.mmd", contents: "")

        let result = DirectoryLister.listFiles(in: tmp.url)

        #expect(result.map(\.lastPathComponent) == ["a.mmd", "b.mmd", "c.mmd"])
    }

    @Test("隠しファイルは除外される")
    func listFilesExcludesHidden() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "")
        _ = try tmp.file(named: "visible.mmd", contents: "")

        let result = DirectoryLister.listFiles(in: tmp.url)

        let names: [String] = result.map(\.lastPathComponent)
        #expect(names == ["visible.mmd"])
    }

    @Test("存在しないディレクトリでは空配列を返す")
    func listFilesReturnsEmptyForMissingDir() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let result = DirectoryLister.listFiles(in: missing)
        #expect(result.isEmpty)
    }
}
