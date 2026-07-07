@testable import befold
import Foundation
import Testing

@Suite
struct SwipeHistoryNavigationTests {
    @Test("しきい値未満のデルタはナビゲーションしない")
    func belowThresholdReturnsNil() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 2, threshold: 10)

        #expect(result == nil)
    }

    @Test("正のデルタ(右スワイプ)は戻る(-1)を返す")
    func positiveDeltaReturnsBack() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 15, threshold: 10)

        #expect(result == -1)
    }

    @Test("負のデルタ(左スワイプ)は進む(+1)を返す")
    func negativeDeltaReturnsForward() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: -15, threshold: 10)

        #expect(result == 1)
    }

    @Test("しきい値ちょうどはナビゲーションする(境界値)")
    func exactlyAtThresholdNavigates() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 10, threshold: 10)

        #expect(result == -1)
    }
}
