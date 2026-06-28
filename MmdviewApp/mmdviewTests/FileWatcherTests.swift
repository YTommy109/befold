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

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // ファイル内容を変更
            try? "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

            // コールバック発火を待つ
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

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // ファイルを削除
            try? FileManager.default.removeItem(at: file)

            // コールバック発火を待つ
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

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // アトミック保存（一時ファイル → rename）をシミュレート
            let tmpFile = tempDir.appendingPathComponent(".test.mmd.tmp")
            try? "graph TD; X-->Y".write(to: tmpFile, atomically: false, encoding: .utf8)
            _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmpFile)

            // コールバック発火を待つ
            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
    }

    /// 存在しないファイルで初期化してもクラッシュせず、stop() も安全に呼べること
    @Test
    func watchingNonexistentFileDoesNotCrash() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-test-\(UUID().uuidString)")
            .appendingPathComponent("nonexistent.mmd")

        let watcher = FileWatcher(path: file) {}
        // クラッシュしないこと自体が検証対象
        watcher.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func stopPreventsCallback() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        nonisolated(unsafe) var callbackFired = false

        let watcher = FileWatcher(path: file) {
            callbackFired = true
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // 監視を停止してからファイルを変更
        watcher.stop()
        try "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

        // 十分待ってもコールバックが呼ばれないこと
        try? await Task.sleep(for: .seconds(1))
        #expect(!callbackFired)
    }
}
