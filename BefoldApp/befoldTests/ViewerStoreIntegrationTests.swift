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
        let firedCount = LockedBox(0)
        store.onFileGone = { firedCount.update { $0 += 1 } }
        store.openFile(file)
        #expect(firedCount.get() == 0)

        try await Task.sleep(for: .seconds(0.3))
        try FileManager.default.removeItem(at: file)

        // onFileGone 発火を待つ（ポーリングで CI 遅延に対応）
        await waitUntil { firedCount.get() == 1 }
        #expect(firedCount.get() == 1)

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

        // content 更新を待つ（ポーリングで CI 遅延に対応）
        await waitUntilOnMainActor { store.content == "graph TD; X-->Y" }
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
