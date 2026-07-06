@testable import befold
import Foundation
import Testing

@Suite
struct DirectoryListerTests {
    @Test("拡張子によらず全ファイルが返される")
    func listFilesReturnsAllFilesRegardlessOfExtension() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "readme.md", contents: "# Hi")
        _ = try tmp.file(named: "photo.png", contents: "binary")
        _ = try tmp.file(named: "data.csv", contents: "a,b")

        let result = DirectoryLister.listFiles(in: tmp.url)

        let names = result.map(\.lastPathComponent)
        #expect(names.contains("diagram.mmd"))
        #expect(names.contains("readme.md"))
        #expect(names.contains("photo.png"))
        #expect(names.contains("data.csv"))
    }

    @Test("サブディレクトリは一覧から除外される")
    func listFilesExcludesDirectories() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "visible.mmd", contents: "")
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )

        let result = DirectoryLister.listFiles(in: tmp.url)

        #expect(result.map(\.lastPathComponent) == ["visible.mmd"])
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
