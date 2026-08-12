import Foundation

/// 監視対象ファイルの「消えた」を確定させる係。
///
/// FileWatcher が不在を検知した直後に確定させると、保存中の置き換え(削除 → 再作成)を
/// 削除と誤認する。グレース期間を置いてから再確認し、まだ無ければ確定させる。
///
/// 待機に使うクロックとグレース期間、張り替え中のタスクをまとめて持つ。
/// `ViewerStore` はこの型を 1 つ保持し、タスクの生存管理には関与しない。
@MainActor
final class FileGoneWatchdog {
    /// 待機に使うクロック。テストでは仮想時刻を注入して実時間依存を排除する。
    private let clock: any Clock<Duration>
    /// FileWatcher のデバウンス既定値に余裕を持たせたグレース期間。
    /// 環境依存のタイミング問題による検知遅延に対応する。
    private let gracePeriod: TimeInterval
    private var task: Task<Void, Never>?

    init(clock: any Clock<Duration>, gracePeriod: TimeInterval) {
        self.clock = clock
        self.gracePeriod = gracePeriod
    }

    /// グレース期間の経過後に `confirm` を呼ぶ。既存の待機は常に張り替える
    /// (発火せず完了したタスクが残って以後の検知を塞ぐことを防ぐ)。
    ///
    /// 不在の再確認は `confirm` 側で行う。schedule 時点の URL をキャプチャすると、
    /// rename とグレース期間の競争状態で「新しいパスは存在するのに閉じる」が起きるため。
    func schedule(confirm: @escaping @MainActor @Sendable () -> Void) {
        cancel()
        task = Task { @MainActor [clock, gracePeriod] in
            try? await clock.sleep(for: .seconds(gracePeriod))
            guard !Task.isCancelled else { return }
            confirm()
        }
    }

    /// 待機中の確定を取り消す。ファイルが再作成された・別ファイルへ切り替えた・閉じたときに呼ぶ。
    func cancel() {
        task?.cancel()
        task = nil
    }
}
