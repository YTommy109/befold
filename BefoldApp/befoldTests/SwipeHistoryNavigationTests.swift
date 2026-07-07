@testable import befold
import Foundation
import Testing

@Suite
struct SwipeHistoryNavigationTests {
    @Test("しきい値未満のデルタはナビゲーションしない")
    func belowThresholdReturnsNil() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 2, verticalDelta: 0, threshold: 10)

        #expect(result == nil)
    }

    @Test("正のデルタ(右スワイプ)は戻る(-1)を返す")
    func positiveDeltaReturnsBack() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 15, verticalDelta: 0, threshold: 10)

        #expect(result == -1)
    }

    @Test("負のデルタ(左スワイプ)は進む(+1)を返す")
    func negativeDeltaReturnsForward() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: -15, verticalDelta: 0, threshold: 10)

        #expect(result == 1)
    }

    @Test("しきい値ちょうどはナビゲーションする(境界値)")
    func exactlyAtThresholdNavigates() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 10, verticalDelta: 0, threshold: 10)

        #expect(result == -1)
    }

    @Test("縦スクロールが優勢な場合はしきい値を超えてもナビゲーションしない")
    func verticalDominantSwipeDoesNotNavigate() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 50, verticalDelta: 80, threshold: 10)

        #expect(result == nil)
    }
}
