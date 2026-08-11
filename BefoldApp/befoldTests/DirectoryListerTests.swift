@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// DirectoryLister への fileReader 注入を検証するためだけの薄いラッパー。
/// DefaultFileReader へ委譲しつつ、指定したファイル名だけ「ディレクトリ」と報告する。
/// DirectoryLister の分類は isDirectory を参照するため、注入した fileReader が
/// 実際に使われていれば、そのファイルはフォルダー扱いになり候補から外れる。
/// (ファイル名で比較するのは、tmp ディレクトリのシンボリックリンク解決有無により
/// FileManager 列挙結果と作成時 URL の path 文字列表現が食い違いうるため)
private struct ExclusionFileReader: FileReading {
    let directoryFileNames: Set<String>
    private let base = DefaultFileReader()

    init(treatingAsDirectory fileNames: [String]) {
        directoryFileNames = Set(fileNames)
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func isDirectory(at url: URL) -> Bool {
        directoryFileNames.contains(url.lastPathComponent) || base.isDirectory(at: url)
    }

    func isExistingFile(at url: URL) -> Bool {
        !directoryFileNames.contains(url.lastPathComponent) && base.isExistingFile(at: url)
    }

    func readString(from url: URL) throws -> String {
        try base.readString(from: url)
    }

    func readData(from url: URL) throws -> Data {
        try base.readData(from: url)
    }

    func isBinary(at url: URL) -> Bool {
        base.isBinary(at: url)
    }

    func fileSize(at url: URL) -> Int? {
        base.fileSize(at: url)
    }

    func modificationDate(at url: URL) -> Date? {
        base.modificationDate(at: url)
    }
}

@Suite
struct DirectoryListerTests {
    @Test("全エントリを隠しファイル込みで localizedStandardCompare 昇順に返す")
    func allEntriesSortedOrdersNaturallyIncludingHidden() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "file10.md", contents: "")
        _ = try tmp.file(named: "file2.md", contents: "")
        _ = try tmp.file(named: ".hidden.md", contents: "")
        _ = try tmp.file(atPath: "sub/inner.md", contents: "") // sub フォルダを作る

        let names = try #require(DirectoryLister.allEntriesSorted(in: tmp.url)).map(\.lastPathComponent)

        // 隠しファイルとサブフォルダも含め全件返る。
        #expect(Set(names) == [".hidden.md", "file2.md", "file10.md", "sub"])
        // 数値を考慮した順序(plain な文字列比較なら file10.md が file2.md より前に来る)。
        let index2 = try #require(names.firstIndex(of: "file2.md"))
        let index10 = try #require(names.firstIndex(of: "file10.md"))
        #expect(index2 < index10)
    }

    @Test("listEntries はダングリングシンボリックリンクを file として含める")
    func listEntriesIncludesDanglingSymlinkAsFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createSymbolicLink(
            at: tmp.url.appendingPathComponent("broken.mmd"),
            withDestinationURL: tmp.url.appendingPathComponent("missing")
        )

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst).rows()
        let broken = entries.first { $0.url.lastPathComponent == "broken.mmd" }

        #expect(broken?.kind == .file)
    }

    @Test("listEntries はフォルダーと拡張子を問わず全ファイルを返す")
    func listEntriesReturnsFoldersAndAllFiles() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tmp = try TempDir(base: home)
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "unknown.xyz", contents: "not skipped anymore")

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst).rows()

        let kinds = entries.map(\.kind)
        let names = entries.map(\.url.lastPathComponent)
        #expect(kinds.first == .parentNavigation)
        #expect(names.contains("subdir"))
        #expect(names.contains("diagram.mmd"))
        #expect(names.contains("unknown.xyz"))
    }

    @Test("listEntries はフォルダーエントリに対応形式ファイルの有無を事前計算する")
    func listEntriesPrecomputesContainsSupportedFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("withSupported"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "withSupported/diagram.mmd", contents: "graph TD;")
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("withoutSupported"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "withoutSupported/unknown.xyz", contents: "not supported")

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst).rows()
        let folders = entries.filter { $0.kind == .folder }

        let withSupported = folders.first { $0.url.lastPathComponent == "withSupported" }
        let withoutSupported = folders.first { $0.url.lastPathComponent == "withoutSupported" }
        #expect(withSupported?.containsSupportedFile == true)
        #expect(withoutSupported?.containsSupportedFile == false)
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

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst).rows()
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

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .alphabetical).rows()
        let nonParent = entries.filter { $0.kind != .parentNavigation }

        #expect(nonParent[0].url.lastPathComponent == "alpha.mmd")
        #expect(nonParent[1].url.lastPathComponent == "beta")
    }

    @Test("listEntries は showHiddenFiles が true のとき不可視ファイル・フォルダーも含める")
    func listEntriesIncludesHiddenWhenShowHiddenFilesIsTrue() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "")
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent(".hiddenDir"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "visible.mmd", contents: "")

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst, showHiddenFiles: true).rows()

        let names = entries.map(\.url.lastPathComponent)
        #expect(names.contains(".hidden.mmd"))
        #expect(names.contains(".hiddenDir"))
        #expect(names.contains("visible.mmd"))
    }

    @Test("listEntries は showHiddenFiles を省略すると不可視ファイル・フォルダーを除外する")
    func listEntriesExcludesHiddenByDefault() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "")
        _ = try tmp.file(named: "visible.mmd", contents: "")

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst).rows()

        let names = entries.map(\.url.lastPathComponent)
        #expect(!names.contains(".hidden.mmd"))
        #expect(names.contains("visible.mmd"))
    }

    @Test("ホームディレクトリでは parentNavigation が含まれない")
    func listEntriesNoParentAtHome() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }

        let entries = DirectoryLister.listing(
            in: home.url, sortOrder: .foldersFirst, home: home.url
        ).rows()

        #expect(!entries.contains { $0.kind == .parentNavigation })
    }

    @Test("ホームディレクトリ配下では parentNavigation が先頭に含まれる")
    func listEntriesHasParentBelowHome() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let tmp = try TempDir(base: home.url)
        defer { withExtendedLifetime(tmp) {} }

        let entries = DirectoryLister.listing(
            in: tmp.url, sortOrder: .foldersFirst, home: home.url
        ).rows()

        #expect(entries.first?.kind == .parentNavigation)
        #expect(entries.first?.url == tmp.url.deletingLastPathComponent())
    }

    @Test("ホームディレクトリ外では parentNavigation が含まれない")
    func listEntriesNoParentOutsideHome() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let entries = DirectoryLister.listing(
            in: tmp.url, sortOrder: .foldersFirst, home: home.url
        ).rows()

        #expect(!entries.contains { $0.kind == .parentNavigation })
    }

    @Test("listingAsync は listing と同じ結果を返す")
    func listingAsyncMatchesSyncVariant() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "diagram.mmd", contents: "graph TD;")

        let syncResult = DirectoryLister.listing(in: tmp.url, sortOrder: .alphabetical)
        let asyncResult = await DirectoryLister.listingAsync(in: tmp.url, sortOrder: .alphabetical)

        #expect(asyncResult == syncResult)
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

    @Test("resolveFileToOpen は対応ファイルがなければ最初のファイルを返す")
    func resolveFileToOpenFallsBackToFirstFileWhenNoSupportedFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "unsupported.xyz", contents: "skip me")

        let result = DirectoryLister.resolveFileToOpen(at: tmp.url)

        #expect(result?.lastPathComponent == "unsupported.xyz")
    }

    @Test("resolveFileToOpen はファイルが1つもないディレクトリで nil を返す")
    func resolveFileToOpenReturnsNilForTrulyEmptyDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

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

    @Test("firstSupportedFile/resolveFileToOpen は fileReader を注入できる")
    func resolveFileToOpenHonorsInjectedFileReader() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.md", contents: "# a")
        _ = try tmp.file(named: "b.md", contents: "# b")
        // DefaultFileReader をラップし、特定のファイル名だけ「ディレクトリ」と報告する fileReader を注入する。
        // 分類は isDirectory を参照するため、注入が実際に使われていれば a.md はフォルダー扱いになり
        // 候補から外れる(無視して常に DefaultFileReader を使っていれば a.md が選ばれてしまう)。
        let reader = ExclusionFileReader(treatingAsDirectory: ["a.md"])

        let firstSupported = DirectoryLister.firstSupportedFile(in: tmp.url, fileReader: reader)
        let resolved = DirectoryLister.resolveFileToOpen(at: tmp.url, fileReader: reader)

        #expect(firstSupported?.lastPathComponent == "b.md")
        #expect(resolved?.lastPathComponent == "b.md")
    }

    @Test("isDirectory は既存ディレクトリで true を返す")
    func isDirectoryReturnsTrueForExistingDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        #expect(DirectoryLister.isDirectory(tmp.url))
    }

    @Test("isDirectory はファイル・存在しないパスで false を返す")
    func isDirectoryReturnsFalseForFileOrMissingPath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")

        #expect(!DirectoryLister.isDirectory(file))
        #expect(!DirectoryLister.isDirectory(missing))
    }

    @Test("isWithinHome はホームディレクトリ自身で true を返す")
    func isWithinHomeReturnsTrueForHomeItself() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL

        #expect(DirectoryLister.isWithinHome(home))
    }

    @Test("isWithinHome はホームディレクトリ配下で true を返す")
    func isWithinHomeReturnsTrueForSubdirectory() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let tmp = try TempDir(base: home.url)
        defer { withExtendedLifetime(tmp) {} }

        #expect(DirectoryLister.isWithinHome(tmp.url, home: home.url))
    }

    @Test("isWithinHome はホームディレクトリ外で false を返す")
    func isWithinHomeReturnsFalseOutsideHome() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        #expect(!DirectoryLister.isWithinHome(tmp.url, home: home.url))
    }

    @Test("isWithinHome は前方一致だけ似た兄弟パスで false を返す")
    func isWithinHomeReturnsFalseForPrefixLikeSiblingPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let sibling = home.deletingLastPathComponent()
            .appendingPathComponent(home.lastPathComponent + "2")

        #expect(!DirectoryLister.isWithinHome(sibling))
    }
}
