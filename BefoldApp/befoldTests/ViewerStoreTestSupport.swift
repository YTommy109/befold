@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation

// ViewerStore 系スイート(ViewerStoreTests / ViewerStoreUnsupportedFileTests /
// ViewerStoreBinaryContentTests / ViewerStoreWatcherCallbackTests /
// ViewerStoreChunkTests / ViewerStoreFileGoneTests ほか)が共有するモックとヘルパー。
// Swift の `private` はファイルスコープなので、複数スイートから使うものはここに集約する。

struct MockFileWatcher: FileWatching {
    func stop() {}
}

/// stop() の呼び出しを数えるだけの FileWatching スタブ。
struct StopCountingWatcher: FileWatching {
    let onStop: @Sendable () -> Void
    func stop() {
        onStop()
    }
}

/// 事前に与えたチャンク列を順に返すモック。最後のチャンクと同時に isAtEnd を返す。
/// バックグラウンドの読み込みタスクから呼ばれるため LockedBox でスレッド安全にする。
final class MockChunkedReader: ChunkedTextReading, @unchecked Sendable {
    private let chunks: [String]
    private let index = LockedBox(0)

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func readNextChunk() async throws -> (text: String, isAtEnd: Bool) {
        let current = index.get()
        guard current < chunks.count else { return ("", true) }
        index.set(current + 1)
        return (chunks[current], current + 1 >= chunks.count)
    }
}

/// 初回チャンクは成功し、2 回目以降の readNextChunk が throw するモック
/// UserDefaults.standard を読むと過去の実行で永続化された値に影響されるため、
/// テストごとに使い捨てのスイートを注入して密閉性を保つ。
/// `onChangeBox` / `onRenameBox` を渡すと watcherFactory に渡されたコールバックを捕捉し、
/// テストから手動で発火できるようにする(ファイル監視イベントのシミュレート用)。
/// - Parameter watcherDebounceDelay: fileGoneGracePeriod(この値の 5 倍)の導出に使う。
///   既定は FileWatcher.defaultDebounceDelay(プロダクト既定 0.2s)であり、
///   ViewerStoreFileGoneTests の 999ms/1ms グレース期間境界テストは
///   グレース期間が 1.0s になることに明示的に依存している(暗黙の既定一致に頼らない)。
@MainActor
func makeStore(
    reader: InMemoryFileReader,
    onChangeBox: LockedBox<(@MainActor @Sendable () -> Void)?>? = nil,
    onRenameBox: LockedBox<(@MainActor @Sendable (URL) -> Void)?>? = nil,
    chunkedReaderFactory: ViewerStore.ChunkedReaderFactory? = nil,
    clock: any Clock<Duration> = ContinuousClock(),
    watcherDebounceDelay: TimeInterval = FileWatcher.defaultDebounceDelay
) -> ViewerStore {
    ViewerStore(
        watcherFactory: { _, _, onChange, onRename in
            onChangeBox?.set(onChange)
            onRenameBox?.set(onRename)
            return MockFileWatcher()
        },
        watcherDebounceDelay: watcherDebounceDelay,
        fileReader: reader,
        chunkedReaderFactory: chunkedReaderFactory,
        defaults: makeIsolatedDefaults(prefix: "ViewerStoreTests"),
        clock: clock
    )
}

/// openFile / 監視コールバックが予約した非同期読み込みの完了を待つ。
@MainActor
func awaitLoad(_ store: ViewerStore) async {
    await store.loadTask?.value
}

/// openFile して非同期読み込みの完了まで待つ(同期読み込み時代の openFile 相当)。
@MainActor
func openAndLoad(_ store: ViewerStore, _ url: URL) async {
    store.openFile(url)
    await awaitLoad(store)
}
