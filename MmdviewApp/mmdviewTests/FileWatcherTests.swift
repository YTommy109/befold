import Testing
import Foundation
@testable import mmdview

@Suite
struct FileWatcherTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsFileModification() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        await confirmation { confirm in
            let watcher = FileWatcher(path: file) {
                confirm()
            }

            try? await Task.sleep(for: .seconds(0.3))
            try? "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsFileDeletion() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        await confirmation { confirm in
            let watcher = FileWatcher(path: file) {
                confirm()
            }

            try? await Task.sleep(for: .seconds(0.3))
            try? FileManager.default.removeItem(at: file)

            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsAtomicSave() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        await confirmation { confirm in
            let watcher = FileWatcher(path: file) {
                confirm()
            }

            try? await Task.sleep(for: .seconds(0.3))
            let tmpFile = tempDir.appendingPathComponent(".test.mmd.tmp")
            try? "graph TD; X-->Y".write(to: tmpFile, atomically: false, encoding: .utf8)
            _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmpFile)

            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
    }
}
