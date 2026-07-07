import Foundation

/// トラックパッドの水平スワイプから履歴ナビゲーション(戻る/進む)の
/// offset を決める純粋ロジック。
enum SwipeHistoryNavigation {
    /// `deltaX` の絶対値が `threshold` 未満、または縦方向の移動量 `deltaY` の絶対値が
    /// `deltaX` の絶対値以上(=縦スクロールが優勢)の場合は nil(ナビゲーションしない)。
    /// 正の deltaX(右向きスワイプ)は戻る(-1)、負(左向き)は進む(+1)を返す。
    static func offset(forHorizontalDelta deltaX: CGFloat, verticalDelta deltaY: CGFloat, threshold: CGFloat) -> Int? {
        guard abs(deltaX) >= threshold, abs(deltaX) > abs(deltaY) else { return nil }
        return deltaX > 0 ? -1 : 1
    }
}
