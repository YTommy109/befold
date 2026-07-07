import Foundation

/// トラックパッドの水平スワイプから履歴ナビゲーション(戻る/進む)の
/// offset を決める純粋ロジック。
enum SwipeHistoryNavigation {
    /// `deltaX` の絶対値が `threshold` 未満なら nil(ナビゲーションしない)。
    /// 正の deltaX(右向きスワイプ)は戻る(-1)、負(左向き)は進む(+1)を返す。
    static func offset(forHorizontalDelta deltaX: CGFloat, threshold: CGFloat) -> Int? {
        guard abs(deltaX) >= threshold else { return nil }
        return deltaX > 0 ? -1 : 1
    }
}
