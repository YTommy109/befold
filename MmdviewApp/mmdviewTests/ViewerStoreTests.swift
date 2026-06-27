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

    @Test
    func openMmdFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        let store = ViewerStore()
        store.openFile(file)

        #expect(store.content == "graph TD; A-->B")
        #expect(store.fileType == .mmd)
        #expect(!store.isDeleted)
        #expect(store.filePath == file)

        store.close()
    }

    @Test
    func openMarkdownFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.md")
        try "# Hello".write(to: file, atomically: true, encoding: .utf8)

        let store = ViewerStore()
        store.openFile(file)

        #expect(store.content == "# Hello")
        #expect(store.fileType == .markdown)
        #expect(!store.isDeleted)

        store.close()
    }

    @Test
    func openNonexistentFileMarksDeleted() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("missing.mmd")

        let store = ViewerStore()
        store.openFile(file)

        #expect(store.isDeleted)
        store.close()
    }

    @Test
    func fileTypeDetection() {
        #expect(FileType(url: URL(fileURLWithPath: "/a/b.mmd")) == .mmd)
        #expect(FileType(url: URL(fileURLWithPath: "/a/b.mermaid")) == .mmd)
        #expect(FileType(url: URL(fileURLWithPath: "/a/b.MMD")) == .mmd)
        #expect(FileType(url: URL(fileURLWithPath: "/a/b.md")) == .markdown)
        #expect(FileType(url: URL(fileURLWithPath: "/a/b.markdown")) == .markdown)
    }
}
