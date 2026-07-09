import AppKit

/// サイドバーが折りたたまれている間、左端に常時表示する薄いハンドル。
/// クリックでサイドバーを再表示するきっかけを与える。
final class CollapsedSidebarHandleView: NSView {
    var onActivate: (() -> Void)?

    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = String(localized: "sidebar.collapsedHandle.tooltip", bundle: .l10n)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = isHovering ? .secondaryLabelColor : .separatorColor
        color.setFill()
        NSBezierPath.fill(bounds)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
