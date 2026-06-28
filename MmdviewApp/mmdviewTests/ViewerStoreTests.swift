import Testing
import Foundation
@testable import mmdview

@Suite
@MainActor
struct ViewerStoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-store-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ファイル種別ごとに内容・種別・状態・パスが正しく設定されること
    @Test(arguments: [
        ("test.mmd", "graph TD; A-->B", FileType.mmd),
        ("test.md", "# Hello", FileType.markdown),
    ])
    func openFileByType(filename: String, content: String, expectedType: FileType) throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent(filename)
        try content.write(to: file, atomically: true, encoding: .utf8)

        let store = ViewerStore()
        store.openFile(file)

        // ファイル内容・種別・状態・パスが正しく設定されること
        #expect(store.content == content)
        #expect(store.fileType == expectedType)
        #expect(!store.isDeleted)
        #expect(store.filePath == file)

        store.close()
    }

    @Test
    func openNonexistentFileMarksDeleted() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("missing.mmd")

        let store = ViewerStore()
        store.openFile(file)

        // 存在しないファイルは isDeleted になること
        #expect(store.isDeleted)
        store.close()
    }

    @Test
    func openEmptyFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("empty.mmd")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let store = ViewerStore()
        store.openFile(file)

        // 空ファイルは空文字列として読み込まれること
        #expect(store.content == "")
        #expect(!store.isDeleted)

        store.close()
    }

    @Test
    func reopenDifferentFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1 つ目のファイルを開く
        let file1 = tempDir.appendingPathComponent("first.mmd")
        try "graph TD; A-->B".write(to: file1, atomically: true, encoding: .utf8)

        let store = ViewerStore()
        store.openFile(file1)
        #expect(store.content == "graph TD; A-->B")
        #expect(store.fileType == .mmd)

        // 別のファイルに切り替え
        let file2 = tempDir.appendingPathComponent("second.md")
        try "# Second".write(to: file2, atomically: true, encoding: .utf8)

        store.openFile(file2)

        // 2 つ目のファイルの内容・種別に切り替わること
        #expect(store.content == "# Second")
        #expect(store.fileType == .markdown)
        #expect(store.filePath == file2)

        store.close()
    }

    /// 監視中にファイルを削除すると isDeleted が true になること
    @Test(.timeLimit(.minutes(1)))
    func deletingWatchedFileMarksDeleted() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        let store = ViewerStore()
        store.openFile(file)
        #expect(!store.isDeleted)

        // 初期化完了を待つ
        try await Task.sleep(for: .seconds(0.3))

        // 監視中にファイルを削除
        try FileManager.default.removeItem(at: file)

        // FileWatcher 経由で isDeleted が更新されるのを待つ
        try await Task.sleep(for: .seconds(3))
        #expect(store.isDeleted)

        store.close()
    }

    /// close() 後はファイルを変更しても content が更新されないこと
    @Test(.timeLimit(.minutes(1)))
    func closeStopsWatching() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        let store = ViewerStore()
        store.openFile(file)
        #expect(store.content == "graph TD; A-->B")

        // 監視を停止
        store.close()
        #expect(store.filePath == file)

        // close() 後にファイルを変更
        try "graph TD; X-->Y".write(to: file, atomically: true, encoding: .utf8)

        // 十分待っても content が更新されないこと
        try await Task.sleep(for: .seconds(1))
        #expect(store.content == "graph TD; A-->B")
    }
}
