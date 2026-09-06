import AppKit

/// スライド窓の前後移動キーを拾うローカルイベントモニタ(TASK-593.3)。
///
/// 形は `SwipeHistoryMonitor` と同じ——窓を弱参照で持ち、`start()` / `stop()` で
/// モニタを出し入れし、判定そのものは純粋な表(`SlideKeyAction`)へ委譲する。
///
/// **`addLocalMonitorForEvents` を使うのは first responder に依らないため。**
/// スライド窓の first responder は WKWebView（本文）なので、responder チェーン上の
/// `keyDown(with:)` を上書きする形だと本文がイベントを先に食う。ローカルモニタは
/// `NSApplication.sendEvent(_:)` より前に呼ばれるので、そこで消費すれば JS 側の
/// `spaceScroll` や `viewer-src/keyboard.ts` の矢印スクロールへは届かない
/// （だから JS 側は触らない）。
@MainActor
final class SlideKeyMonitor {
    private weak var window: NSWindow?
    private let onMove: (SlideKeyAction) -> Void
    private var monitor: Any?

    /// - Parameter window: 検知対象のウィンドウ。他ウィンドウ宛のイベントは無視する。
    /// - Parameter onMove: `.next` / `.previous` の通知先。`.ignored` は渡らない。
    init(window: NSWindow, onMove: @escaping (SlideKeyAction) -> Void) {
        self.window = window
        self.onMove = onMove
    }

    /// ローカルイベントモニタを登録する。ウィンドウ生成後、一度だけ呼ぶこと。
    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, handle(event) else { return event }
            // 扱ったイベントは nil を返して消費する。返すと本文にも届き、
            // Space がページ送りとファイル送りの両方を起こす。
            return nil
        }
    }

    /// ローカルイベントモニタを解除する。ウィンドウが閉じるときに呼ぶこと。
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// 扱ったら true（呼び出し側がイベントを消費する）。
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let action = SlideKeyAction.action(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            isEditingText: Self.isEditingText(in: window)
        )
        guard action != .ignored else { return false }
        onMove(action)
        return true
    }

    /// テキスト入力中か。`NSTextField` は編集中に field editor(`NSTextView`)を
    /// first responder にするため、実際に当たるのはほとんど前者だが、
    /// **両方を見る**（片方だけだと検索欄の実装が変わったときに静かに破れる）。
    static func isEditingText(in window: NSWindow) -> Bool {
        window.firstResponder is NSText || window.firstResponder is NSTextField
    }
}
