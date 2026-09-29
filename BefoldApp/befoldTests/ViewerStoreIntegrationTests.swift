@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 統合テスト用の短い debounce。プロダクト既定の 0.2s では TSan スローダウン下で
/// 伝搬チェーンが長くなりタイムアウトしやすいため、テストでは短い値を注入して
/// 所要時間とマージンを改善する。ViewerStore の watcherDebounceDelay に渡すと、
/// makeWatcher(WatcherFactory)の第 2 引数として同じ値が渡ってくるため、
/// fastWatcherFactory 側で値を再度ハードコードする必要はない
/// (fileGoneGracePeriod もこの値の 5 倍として連動して短縮される)。
private let testDebounceDelay: TimeInterval = 0.05

/// 実ファイルシステム + 実 FileWatcher で、通知が `@MainActor` の ViewerStore まで
/// 届くことを見る。FileWatcher の検知ロジック自体は FileWatcherIntegrationTests、
/// close で監視が止まることは `ViewerStoreTests.closeStopsWatcher` が見る。
///
/// かつては FileWatcherIntegrationTests と同じ根拠(並列時のイベント配送遅延、
/// docs/dev/flaky-test-filewatcher-investigation.md「追加対策 6」)で直列化していたが、
/// 待機はどれも条件待ちで、直列化を外して 3 回連続で緑を確認した(TASK-662.4)。
@Suite
@MainActor
struct ViewerStoreIntegrationTests {
    /// 実 FileWatcher を短い debounce で生成する watcherFactory。
    /// debounceDelay は ViewerStore から渡された値(watcherDebounceDelay と同一)を
    /// そのまま使う。
    private static func fastWatcherFactory() -> ViewerStore.WatcherFactory {
        { url, debounceDelay, onChange, onRename in
            FileWatcher(
                path: url,
                debounceDelay: debounceDelay,
                renameSettleDelay: debounceDelay,
                onChange: onChange,
                onRename: onRename
            )
        }
    }

    @Test(testTimeLimit())
    func deletingWatchedFileFiresOnFileGone() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let store = ViewerStore(watcherFactory: Self.fastWatcherFactory(), watcherDebounceDelay: testDebounceDelay)
        let firedCount = LockedBox(0)
        store.onFileGone = { firedCount.update { $0 += 1 } }
        store.openFile(file)
        // 読み込みは非同期のため、初回読み込みの完了を待ってから後続の書き換え検知に進む。
        await store.loadTask?.value
        #expect(store.contentState.content == "graph TD; A-->B")
        #expect(firedCount.get() == 0)

        // 削除は一度きり（エッジトリガー）で再実行できず、kevent 登録は resume 後に
        // 非同期完了するため、登録前に削除するとイベントを取りこぼす。content を書き換えて
        // 更新が届くのを待ち、file source の登録完了を観測してから削除する。
        // content 更新は onFileGone に影響しないため静穏化は不要。
        await waitUntilWithRetryOnMainActor(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: file, atomically: false, encoding: .utf8)
        }, until: {
            store.contentState.content != "graph TD; A-->B"
        })

        try FileManager.default.removeItem(at: file)

        // onFileGone 発火を待つ（ポーリングで CI 遅延に対応）
        await waitUntil { firedCount.get() == 1 }
        #expect(firedCount.get() == 1)

        store.close()
    }

    @Test(testTimeLimit())
    func reflectsFileEditAfterDebounce() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let store = ViewerStore(watcherFactory: Self.fastWatcherFactory(), watcherDebounceDelay: testDebounceDelay)
        store.openFile(file)
        // 読み込みは非同期のため、完了を待ってから検証する。
        await store.loadTask?.value
        #expect(store.contentState.content == "graph TD; A-->B")

        // 実ファイルを編集 → デバウンス後に content が更新される。
        // 監視再開の遅れに強いよう、更新されるまで書き込みを繰り返す。
        await waitUntilWithRetryOnMainActor(action: {
            try? "graph TD; X-->Y".write(to: file, atomically: true, encoding: .utf8)
        }, until: {
            store.contentState.content == "graph TD; X-->Y"
        })
        #expect(store.contentState.content == "graph TD; X-->Y")

        store.close()
    }
}
