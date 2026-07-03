import AppKit

/// ダウンロード進捗を表示する小ウィンドウ(GUI 層・自動テスト対象外)。
@MainActor
final class DownloadProgressWindowController: NSWindowController {
    private let indicator = NSProgressIndicator()

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "アップデートをダウンロード中…"
        window.center()
        super.init(window: window)

        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.frame = NSRect(x: 20, y: 26, width: 280, height: 20)
        window.contentView?.addSubview(indicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setProgress(_ value: Double) {
        indicator.doubleValue = value
    }
}
