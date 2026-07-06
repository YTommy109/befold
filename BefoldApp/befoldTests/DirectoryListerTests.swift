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

    @Test("listEntries はフォルダーと対応ファイルを返し、非対応ファイルを除外する")
    func listEntriesReturnsFoldersAndSupportedFiles() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tmp = try TempDir(base: home)
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "unknown.xyz", contents: "skip me")

        let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)

        let kinds = entries.map(\.kind)
        let names = entries.map(\.url.lastPathComponent)
        #expect(kinds.first == .parentNavigation)
        #expect(names.contains("subdir"))
        #expect(names.contains("diagram.mmd"))
        #expect(!names.contains("unknown.xyz"))
    }

    @Test("foldersFirst ソートではフォルダーがファイルより先に並ぶ")
    func listEntriesFoldersFirstSort() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("zebra"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "alpha.mmd", contents: "")

        let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)
        let nonParent = entries.filter { $0.kind != .parentNavigation }

        #expect(nonParent[0].kind == .folder)
        #expect(nonParent[0].url.lastPathComponent == "zebra")
        #expect(nonParent[1].kind == .file)
        #expect(nonParent[1].url.lastPathComponent == "alpha.mmd")
    }

    @Test("alphabetical ソートではフォルダーとファイルが名前順で混在する")
    func listEntriesAlphabeticalSort() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("beta"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "alpha.mmd", contents: "")

        let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .alphabetical)
        let nonParent = entries.filter { $0.kind != .parentNavigation }

        #expect(nonParent[0].url.lastPathComponent == "alpha.mmd")
        #expect(nonParent[1].url.lastPathComponent == "beta")
    }

    @Test("ホームディレクトリでは parentNavigation が含まれない")
    func listEntriesNoParentAtHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let entries = DirectoryLister.listEntries(in: home, sortOrder: .foldersFirst)

        #expect(!entries.contains { $0.kind == .parentNavigation })
    }

    @Test("ホームディレクトリ配下では parentNavigation が先頭に含まれる")
    func listEntriesHasParentBelowHome() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tmp = try TempDir(base: home)
        defer { withExtendedLifetime(tmp) {} }

        let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)

        #expect(entries.first?.kind == .parentNavigation)
        #expect(entries.first?.url == tmp.url.deletingLastPathComponent())
    }

    @Test("ホームディレクトリ外では parentNavigation が含まれない")
    func listEntriesNoParentOutsideHome() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)

        #expect(!entries.contains { $0.kind == .parentNavigation })
    }

    @Test("resolveFileToOpen はディレクトリを渡すと最初の対応ファイルを返す")
    func resolveFileToOpenReturnsFirstSupportedFileForDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "b.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "a.mmd", contents: "graph TD;")

        let result = DirectoryLister.resolveFileToOpen(at: tmp.url)

        #expect(result?.lastPathComponent == "a.mmd")
    }

    @Test("resolveFileToOpen は対応ファイルのないディレクトリで nil を返す")
    func resolveFileToOpenReturnsNilForEmptyDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "unsupported.xyz", contents: "skip me")

        let result = DirectoryLister.resolveFileToOpen(at: tmp.url)

        #expect(result == nil)
    }

    @Test("resolveFileToOpen はファイルパスをそのまま返す")
    func resolveFileToOpenReturnsFileUnchanged() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")

        let result = DirectoryLister.resolveFileToOpen(at: file)

        #expect(result == file)
    }

    @Test("resolveFileToOpen は存在しないパスをそのまま返す")
    func resolveFileToOpenReturnsMissingPathUnchanged() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")

        let result = DirectoryLister.resolveFileToOpen(at: missing)

        #expect(result == missing)
    }
}
