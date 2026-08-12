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

/// 実ファイルシステム + 実 FileWatcher を使うため直列化する。
/// 並列実行では複数の GCD キュー・DispatchSource が CI の少コアランナー上で
/// リソースを奪い合い、イベント配送が遅れてフレーキーになるため
/// (docs/dev/flaky-test-filewatcher-investigation.md「追加対策 6」)。
///
/// 注: この根拠は FileWatcherIntegrationTests(本タスクで .serialized を解除済み)と
/// 同一であり、両スイートを構造的に区別する固有の理由は見つかっていない
/// (このドキュメントの調査時点では両方に同じ理由で .serialized を付与していた)。
/// FileWatcherIntegrationTests 側は今回 3 回連続実行(--filter 単独 + フル swift test)で
/// 安定を確認した上で解除したが、ViewerStoreIntegrationTests 側は本タスクのスコープでは
/// 未検証のため、予防的に直列のまま維持する。
@Suite(.serialized)
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

    @Test(testTimeLimit())
    func closeStopsWatching() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let store = ViewerStore(watcherFactory: Self.fastWatcherFactory(), watcherDebounceDelay: testDebounceDelay)
        store.openFile(file)
        // 読み込みは非同期のため、完了を待ってから検証する。
        await store.loadTask?.value
        #expect(store.contentState.content == "graph TD; A-->B")

        store.close()
        #expect(store.contentState.filePath == file)

        try "graph TD; X-->Y".write(to: file, atomically: true, encoding: .utf8)

        // close 後は変更が反映されないこと（発火しないことの確認なので固定待ち）。
        // atomically: true の書き込みは rename 経由(renameSettleDelay → debounce → MainActor、
        // FileWatcher.swift:108-160)で、さらに万一 onChange が発火すれば ViewerStore の
        // 非同期再読込(loadContent → apply)が後段に乗る。万一 close() のリークで発火しても
        // 反映され得る最大経路長 testDebounceDelay(renameSettleDelay) + testDebounceDelay(debounce)
        // を基準に + 0.3s の余裕を持たせ、時限の境界を確実に跨ぐ(docs/dev/coding_rule.md 参照)。
        try await Task.sleep(for: .seconds(testDebounceDelay + testDebounceDelay + 0.3))
        #expect(store.contentState.content == "graph TD; A-->B")
    }
}
