import AppKit

/// 二本指スワイプ(トラックパッド)によるファイル履歴の戻る/進むを検知する。
/// NSEvent のローカルモニタの登録/解除と、phase ごとのデルタ積算ステートマシンを保持する。
/// 閾値判定そのものは SwipeHistoryNavigation(純粋ロジック)へ委譲する。
@MainActor
final class SwipeHistoryMonitor {
    /// スワイプしきい値(pt)。この値未満の水平デルタはナビゲーションしない。
    private static let swipeThreshold: CGFloat = 40

    private weak var window: NSWindow?
    private let onNavigate: (Int) -> Void
    private var monitor: Any?
    /// スワイプジェスチャー中(.began〜.changed)に積算する水平デルタ。.ended で判定に使う。
    private var horizontalAccumulator: CGFloat = 0
    /// スワイプジェスチャー中(.began〜.changed)に積算する垂直デルタ。.ended で判定に使う。
    private var verticalAccumulator: CGFloat = 0

    /// - Parameter window: スワイプ検知対象のウィンドウ。他ウィンドウ宛のイベントは無視する。
    /// - Parameter onNavigate: しきい値判定を通過したときの通知先。offset 負=戻る / 正=進む。
    init(window: NSWindow, onNavigate: @escaping (Int) -> Void) {
        self.window = window
        self.onNavigate = onNavigate
    }

    /// ローカルイベントモニタを登録する。ウィンドウ生成後、一度だけ呼ぶこと。
    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event)
            return event
        }
    }

    /// ローカルイベントモニタを解除する。ウィンドウが閉じるときに呼ぶこと。
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard event.window === window else { return }
        handlePhase(event.phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
    }

    /// .began でリセットし、.changed で水平・垂直デルタを積算し、.ended で
    /// 積算値をしきい値判定する(単一フレームの .ended デルタはほぼ0になるため)。
    /// 垂直デルタも積算するのは、縦スクロール中の横ドリフト蓄積による誤発火を
    /// 防ぐため(横優勢のときのみナビゲーションする、SwipeHistoryNavigation 側で判定)。
    func handlePhase(_ phase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat) {
        switch phase {
        case .began:
            horizontalAccumulator = 0
            verticalAccumulator = 0
        case .changed:
            horizontalAccumulator += deltaX
            verticalAccumulator += deltaY
        case .ended:
            defer {
                horizontalAccumulator = 0
                verticalAccumulator = 0
            }
            guard let offset = SwipeHistoryNavigation.offset(
                forHorizontalDelta: horizontalAccumulator,
                verticalDelta: verticalAccumulator,
                threshold: Self.swipeThreshold
            ) else { return }
            onNavigate(offset)
        default:
            break
        }
    }
}
