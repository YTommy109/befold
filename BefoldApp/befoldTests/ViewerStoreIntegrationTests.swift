@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct ViewerStoreIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func deletingWatchedFileFiresOnFileGone() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let store = ViewerStore()
        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)
        #expect(firedCount == 0)

        try await Task.sleep(for: .seconds(0.3))
        try FileManager.default.removeItem(at: file)

        try await Task.sleep(for: .seconds(3))
        #expect(firedCount == 1)

        store.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func reflectsFileEditAfterDebounce() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let store = ViewerStore()
        store.openFile(file)
        #expect(store.content == "graph TD; A-->B")

        // 監視の初期化完了を待つ
        try await Task.sleep(for: .seconds(0.3))

        // 実ファイルを編集 → デバウンス(0.2s)後に content が更新される
        try "graph TD; X-->Y".write(to: file, atomically: true, encoding: .utf8)

        try await Task.sleep(for: .seconds(3))
        #expect(store.content == "graph TD; X-->Y")

        store.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func closeStopsWatching() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let store = ViewerStore()
        store.openFile(file)
        #expect(store.content == "graph TD; A-->B")

        store.close()
        #expect(store.filePath == file)

        try "graph TD; X-->Y".write(to: file, atomically: true, encoding: .utf8)

        try await Task.sleep(for: .seconds(1))
        #expect(store.content == "graph TD; A-->B")
    }
}
