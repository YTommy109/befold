@testable import befold
import Foundation
import Testing

/// フォルダー一覧の行メタデータ(TASK-707)。
struct FolderListingMetadataTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderListingMetadataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("ファイルは変更日・サイズ・種類、フォルダーはサイズ空欄")
    func filesHaveSizeFoldersDoNot() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.md")
        try Data("hello".utf8).write(to: file)
        let folder = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

        let loaded = await FolderListingMetadata.load(for: [file, folder])

        #expect(loaded[file]?.size == 5)
        #expect(loaded[file]?.modified != nil)
        #expect(loaded[file]?.kind?.isEmpty == false)
        #expect(loaded[folder]?.size == nil)
        #expect(loaded[folder]?.modified != nil)
        #expect(loaded[folder]?.kind?.isEmpty == false)
    }

    @Test("再取得すると更新後のサイズが返る(行の更新が追随する)")
    func reloadReflectsContentChange() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.md")
        try Data("12".utf8).write(to: file)
        #expect(await FolderListingMetadata.load(for: [file])[file]?.size == 2)
        try Data("1234567".utf8).write(to: file)
        #expect(await FolderListingMetadata.load(for: [file])[file]?.size == 7)
    }

    @Test("読めない URL は辞書に載せない")
    func missingFileIsOmitted() async {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/x.md")
        #expect(await FolderListingMetadata.load(for: [missing]).isEmpty)
    }
}
