@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 最後の参照が監視キュー上で外れても、`FileWatcher` の解放でプロセスが落ちないこと(TASK-663)。
///
/// init の `queue.async { self... }` は self を強参照で持つ。作ってすぐ手放すと、最後の解放は
/// そのブロックの破棄(監視キュー上)になり、deinit から `queue.sync` していた頃は
/// libdispatch が「自分が持つキューへの dispatch_sync」として trap した
/// (`swift test` が `unexpected signal code 5` で落ちる)。
struct FileWatcherReleaseOnWatcherQueueTests {
    private final class WeakWatcher: @unchecked Sendable {
        weak var value: FileWatcher?
    }

    @Test("作ってすぐ手放した FileWatcher が監視キュー上で解放されても落ちない")
    func releasingRightAfterInitDoesNotTrap() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let file = try temp.file(named: "a.md", contents: "x")
        // 1 回では監視開始のブロックが先に終わって呼び出し側で解放されることがあるため、
        // 何度か繰り返して監視キュー上での解放を確実に踏ませる。
        let watchers = (0 ..< 20).map { _ in
            let weak = WeakWatcher()
            weak.value = FileWatcher(path: file, onChangeOnWatcherQueue: {})
            return weak
        }

        await waitUntil { watchers.allSatisfy { $0.value == nil } }
    }
}
