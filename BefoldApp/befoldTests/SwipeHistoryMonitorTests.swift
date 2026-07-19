import AppKit
@testable import befold
import Testing

/// handlePhase の直接呼び出しでアキュムレータ・しきい値判定を検証する。
/// start/stop の AppKit ランタイム依存部分(NSEvent モニタ登録)はユニットテスト対象外。
@Suite
@MainActor
struct SwipeHistoryMonitorTests {
    private func makeMonitor(onNavigate: @escaping (Int) -> Void) -> SwipeHistoryMonitor {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false
        )
        return SwipeHistoryMonitor(window: window, onNavigate: onNavigate)
    }

    @Test(".began 〜 .changed の積算がしきい値を超えると .ended で戻る(-1)を通知する")
    func rightSwipeAboveThresholdNavigatesBack() {
        var offsets: [Int] = []
        let monitor = makeMonitor { offsets.append($0) }

        monitor.handlePhase(.began, deltaX: 0, deltaY: 0)
        monitor.handlePhase(.changed, deltaX: 30, deltaY: 0)
        monitor.handlePhase(.changed, deltaX: 20, deltaY: 0)
        monitor.handlePhase(.ended, deltaX: 0, deltaY: 0)

        #expect(offsets == [-1])
    }

    @Test(".began 〜 .changed の積算がしきい値を超える負のデルタは .ended で進む(+1)を通知する")
    func leftSwipeAboveThresholdNavigatesForward() {
        var offsets: [Int] = []
        let monitor = makeMonitor { offsets.append($0) }

        monitor.handlePhase(.began, deltaX: 0, deltaY: 0)
        monitor.handlePhase(.changed, deltaX: -30, deltaY: 0)
        monitor.handlePhase(.changed, deltaX: -20, deltaY: 0)
        monitor.handlePhase(.ended, deltaX: 0, deltaY: 0)

        #expect(offsets == [1])
    }

    @Test("しきい値未満の積算では .ended で通知しない")
    func belowThresholdDoesNotNavigate() {
        var offsets: [Int] = []
        let monitor = makeMonitor { offsets.append($0) }

        monitor.handlePhase(.began, deltaX: 0, deltaY: 0)
        monitor.handlePhase(.changed, deltaX: 10, deltaY: 0)
        monitor.handlePhase(.ended, deltaX: 0, deltaY: 0)

        #expect(offsets.isEmpty)
    }

    @Test("縦スクロールが優勢な積算では .ended で通知しない")
    func verticalDominantSwipeDoesNotNavigate() {
        var offsets: [Int] = []
        let monitor = makeMonitor { offsets.append($0) }

        monitor.handlePhase(.began, deltaX: 0, deltaY: 0)
        monitor.handlePhase(.changed, deltaX: 50, deltaY: 80)
        monitor.handlePhase(.ended, deltaX: 0, deltaY: 0)

        #expect(offsets.isEmpty)
    }

    @Test(".began は前回ジェスチャーの積算をリセットする")
    func beganResetsPreviousAccumulation() {
        var offsets: [Int] = []
        let monitor = makeMonitor { offsets.append($0) }

        monitor.handlePhase(.began, deltaX: 0, deltaY: 0)
        monitor.handlePhase(.changed, deltaX: 50, deltaY: 0)
        // 積算未確定のまま新しいジェスチャーが始まるとリセットされる。
        monitor.handlePhase(.began, deltaX: 0, deltaY: 0)
        monitor.handlePhase(.ended, deltaX: 0, deltaY: 0)

        #expect(offsets.isEmpty)
    }
}
