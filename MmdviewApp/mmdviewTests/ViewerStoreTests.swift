import Foundation
@testable import mmdview
import Testing

private struct MockFileWatcher: FileWatching {
    func stop() {}
}

@Suite
@MainActor
struct ViewerStoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-store-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore() -> ViewerStore {
        ViewerStore { _, _ in MockFileWatcher() }
    }

    @Test(arguments: [
        ("test.mmd", "graph TD; A-->B", FileType.mmd),
        ("test.md", "# Hello", FileType.markdown),
    ])
    func openFileByType(filename: String, content: String, expectedType: FileType) throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent(filename)
        try content.write(to: file, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(file)

        #expect(store.content == content)
        #expect(store.fileType == expectedType)
        #expect(!store.isDeleted)
        #expect(store.filePath == file)

        store.close()
    }

    @Test
    func openNonexistentFileMarksDeleted() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("missing.mmd")

        let store = makeStore()
        store.openFile(file)

        #expect(store.isDeleted)
        store.close()
    }

    @Test
    func openEmptyFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("empty.mmd")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(file)

        #expect(store.content == "")
        #expect(!store.isDeleted)

        store.close()
    }

    @Test
    func reopenDifferentFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("first.mmd")
        try "graph TD; A-->B".write(to: file1, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(file1)
        #expect(store.content == "graph TD; A-->B")
        #expect(store.fileType == .mmd)

        let file2 = tempDir.appendingPathComponent("second.md")
        try "# Second".write(to: file2, atomically: true, encoding: .utf8)

        store.openFile(file2)

        #expect(store.content == "# Second")
        #expect(store.fileType == .markdown)
        #expect(store.filePath == file2)

        store.close()
    }

    @Test
    func watcherCallbackReloadsContent() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        // factory に渡された onChange を保持する
        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore { _, callback in
            onChange = callback
            return MockFileWatcher()
        }
        store.openFile(file)
        #expect(store.content == "graph TD; A-->B")

        // ファイル内容を書き換えてから監視コールバックを発火する
        try "graph TD; X-->Y".write(to: file, atomically: true, encoding: .utf8)
        onChange?()

        #expect(store.content == "graph TD; X-->Y")

        store.close()
    }

    @Test
    func watcherCallbackTracksDeletionAndRecreation() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore { _, callback in
            onChange = callback
            return MockFileWatcher()
        }
        store.openFile(file)
        #expect(!store.isDeleted)

        // ファイル削除 → コールバック発火で isDeleted が立つ
        try FileManager.default.removeItem(at: file)
        onChange?()
        #expect(store.isDeleted)

        // 再作成 → コールバック発火で isDeleted が戻り、新しい内容が読める
        try "graph TD; C-->D".write(to: file, atomically: true, encoding: .utf8)
        onChange?()
        #expect(!store.isDeleted)
        #expect(store.content == "graph TD; C-->D")

        store.close()
    }

    @Test
    func openFileStopsPreviousWatcher() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        nonisolated(unsafe) var stopCount = 0
        let store = ViewerStore { _, _ in
            StopCountingWatcher { stopCount += 1 }
        }

        let file1 = tempDir.appendingPathComponent("a.mmd")
        try "A".write(to: file1, atomically: true, encoding: .utf8)
        store.openFile(file1)
        #expect(stopCount == 0)

        let file2 = tempDir.appendingPathComponent("b.mmd")
        try "B".write(to: file2, atomically: true, encoding: .utf8)
        store.openFile(file2)
        #expect(stopCount == 1)

        store.close()
    }
}

private struct StopCountingWatcher: FileWatching {
    let onStop: @Sendable () -> Void
    func stop() {
        onStop()
    }
}
