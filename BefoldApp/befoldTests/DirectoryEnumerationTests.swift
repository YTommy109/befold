import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 列挙・分類・ソートと先頭対応ファイル判定の単一の実装元(BefoldKit.DirectoryEnumeration)の検証。
struct DirectoryEnumerationTests {
    private let fileReader = DefaultFileReader()

    @Test("sortedContents はフォルダとファイルを分類し、それぞれ自然順で返す")
    func sortedContentsClassifiesAndSortsNaturally() throws {
        let temp = try TempDir()
        _ = try temp.file(named: "b10.md", contents: "")
        _ = try temp.file(named: "b2.md", contents: "")
        for name in ["zdir", "adir"] {
            try FileManager.default.createDirectory(
                at: temp.url.appendingPathComponent(name), withIntermediateDirectories: true
            )
        }

        let result = DirectoryEnumeration.sortedContents(in: temp.url, fileReader: fileReader)

        #expect(result.folders.map(\.lastPathComponent) == ["adir", "zdir"])
        #expect(result.files.map(\.lastPathComponent) == ["b2.md", "b10.md"])
    }

    @Test("showHiddenFiles が false なら隠しファイルを除外し、true なら含める")
    func sortedContentsHonorsShowHiddenFiles() throws {
        let temp = try TempDir()
        _ = try temp.file(named: ".hidden.md", contents: "")
        _ = try temp.file(named: "visible.md", contents: "")

        let hidden = DirectoryEnumeration.sortedFiles(in: temp.url, fileReader: fileReader)
        #expect(hidden.map(\.lastPathComponent) == ["visible.md"])

        let shown = DirectoryEnumeration.sortedFiles(in: temp.url, showHiddenFiles: true, fileReader: fileReader)
        #expect(shown.map(\.lastPathComponent) == [".hidden.md", "visible.md"])
    }

    @Test("列挙できないパスでは空の組を返す")
    func sortedContentsReturnsEmptyForMissingDirectory() {
        let missing = URL(fileURLWithPath: "/nonexistent-befold-dir-\(UUID().uuidString)")
        let result = DirectoryEnumeration.sortedContents(in: missing, fileReader: fileReader)
        #expect(result.folders.isEmpty)
        #expect(result.files.isEmpty)
    }

    @Test("ダングリングシンボリックリンクも files に算入する")
    func sortedFilesIncludesDanglingSymlink() throws {
        let temp = try TempDir()
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("dangling.mmd"),
            withDestinationURL: temp.url.appendingPathComponent("missing-target.mmd")
        )

        let files = DirectoryEnumeration.sortedFiles(in: temp.url, fileReader: fileReader)
        #expect(files.map(\.lastPathComponent) == ["dangling.mmd"])
    }

    @Test("firstSupportedFile は自然順で最初の対応形式ファイルを返す")
    func firstSupportedFileReturnsFirstSupported() throws {
        let temp = try TempDir()
        _ = try temp.file(named: "a.txt", contents: "")
        _ = try temp.file(named: "b10.md", contents: "")
        _ = try temp.file(named: "b2.md", contents: "")

        let first = DirectoryEnumeration.firstSupportedFile(in: temp.url, fileReader: fileReader)
        #expect(first?.lastPathComponent == "b2.md")
    }

    @Test("対応形式が無ければ firstSupportedFile は nil を返す")
    func firstSupportedFileReturnsNilWhenNoneSupported() throws {
        let temp = try TempDir()
        _ = try temp.file(named: "a.bin", contents: "")

        #expect(DirectoryEnumeration.firstSupportedFile(in: temp.url, fileReader: fileReader) == nil)
    }

    @Test("resolveFileToOpen は対応形式を優先し、無ければ先頭ファイルへフォールバックする")
    func resolveFileToOpenPrefersSupportedThenFallsBack() throws {
        let supportedDir = try TempDir()
        _ = try supportedDir.file(named: "a.txt", contents: "")
        _ = try supportedDir.file(named: "b.md", contents: "")
        #expect(
            SupportedFileResolver.resolveFileToOpen(at: supportedDir.url, fileReader: fileReader)?
                .lastPathComponent == "b.md"
        )

        let unsupportedDir = try TempDir()
        _ = try unsupportedDir.file(named: "z.bin", contents: "")
        _ = try unsupportedDir.file(named: "a.bin", contents: "")
        #expect(
            SupportedFileResolver.resolveFileToOpen(at: unsupportedDir.url, fileReader: fileReader)?
                .lastPathComponent == "a.bin"
        )
    }

    @Test("ソート済み 2 列のマージは、連結してソートし直した並びと一致する")
    func mergeMatchesFullSort() {
        // 数字の桁・大文字小文字・非 ASCII・拡張子の有無を混ぜ、localizedStandardCompare の
        // 効き方が並びに出るようにする。フォルダー側とファイル側が交互に来る組にしている。
        let folderNames = ["Apple", "file2", "ふぉるだ", "z-dir", "項目10"]
        let fileNames = ["apple.md", "file10.md", "file2.md", "ふぁいる.md", "項目2.md"]
        let base = URL(fileURLWithPath: "/tmp/merge-by-file-name")
        let folders = folderNames.map { base.appendingPathComponent($0) }.sortedByFileName()
        let files = fileNames.map { base.appendingPathComponent($0) }.sortedByFileName()

        let merged = [URL].mergedByFileName(folders, files, name: \.lastPathComponent)

        #expect(merged.map(\.lastPathComponent) == (folders + files).sortedByFileName().map(\.lastPathComponent))
        #expect(merged.count == folders.count + files.count)
    }

    @Test("マージは片側が空でも、もう片側の並びをそのまま返す")
    func mergeHandlesEmptySide() {
        let base = URL(fileURLWithPath: "/tmp/merge-by-file-name")
        let files = ["b.md", "a.md"].map { base.appendingPathComponent($0) }.sortedByFileName()

        #expect([URL].mergedByFileName([], files, name: \.lastPathComponent) == files)
        #expect([URL].mergedByFileName(files, [], name: \.lastPathComponent) == files)
        #expect([URL].mergedByFileName([], [], name: \.lastPathComponent).isEmpty)
    }
}
