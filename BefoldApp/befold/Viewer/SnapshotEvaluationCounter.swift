#if DEBUG
    /// `FileListModel.listSnapshot` を評価した回数だけを持つ計数器(TASK-418 AC#3)。
    ///
    /// モデル本体から出してあるのは、これがテスト計測のための足場であって
    /// サイドバーの状態ではないため。参照型なので `FileListModel` 側は `let` 1 本で持て、
    /// 「読み出しが再描画を呼ばない」(`@ObservationIgnored`)という元の性質も変わらない。
    @MainActor
    final class SnapshotEvaluationCounter {
        /// これまでの評価回数。
        private(set) var count = 0

        /// 1 回評価したことを記録する。`listSnapshot` の導出から呼ぶ。
        func note() {
            count += 1
        }

        /// 0 へ戻す。測りたい操作の直前にテストから呼ぶ。
        func reset() {
            count = 0
        }
    }
#endif
