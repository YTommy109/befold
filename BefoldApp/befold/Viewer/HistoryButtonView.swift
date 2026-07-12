import AppKit

/// 戻る/進むのツールバーボタン。クリックで primary 移動(戻る/進む 1 段)、
/// 長押し・右クリック・Cmd/Ctrl+クリックで履歴メニューをポップアップする。
final class HistoryButtonView: NSButton {
    /// クリック時に移動する履歴オフセット(-1=戻る / +1=進む)。
    private var primaryOffset = -1
    /// 履歴メニューに表示するエントリ(現在位置に近い順)。
    private var entries: [HistoryEntry] = []
    private var onNavigate: ((Int) -> Void)?

    convenience init(
        systemImage: String,
        accessibilityLabel: String,
        primaryOffset: Int,
        onNavigate: @escaping (Int) -> Void
    ) {
        self.init(frame: .zero)
        self.primaryOffset = primaryOffset
        self.onNavigate = onNavigate
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.momentaryPushIn)
        image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: accessibilityLabel
        )
        isEnabled = false
    }

    /// 履歴状態の変化をボタンへ反映する。
    func updateState(isEnabled: Bool, entries: [HistoryEntry]) {
        self.isEnabled = isEnabled
        self.entries = entries
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        // NSButton では Ctrl+click が rightMouseDown へ転送されない場合がある
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }

        highlight(true)
        let deadline = Date(timeIntervalSinceNow: 0.3)
        var clickedInside = false
        var mouseUp = false
        while let next = window?.nextEvent(
            matching: [.leftMouseUp, .leftMouseDragged],
            until: deadline,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if next.type == .leftMouseUp {
                mouseUp = true
                let location = convert(next.locationInWindow, from: nil)
                clickedInside = bounds.contains(location)
                break
            }
        }
        highlight(false)

        if clickedInside {
            onNavigate?(primaryOffset)
        } else if !mouseUp {
            showMenu()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        showMenu()
    }

    private func showMenu() {
        guard !entries.isEmpty else { return }
        let menu = NSMenu()
        let direction = primaryOffset < 0 ? -1 : 1
        for (index, entry) in entries.enumerated() {
            let (title, icon) = Self.menuLabel(for: entry)
            let item = NSMenuItem(
                title: title,
                action: #selector(menuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.image = icon
            item.target = self
            item.tag = direction * (index + 1)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
    }

    private static func menuLabel(for entry: HistoryEntry) -> (String, NSImage) {
        if let file = entry.file {
            let dirName = entry.directory.lastPathComponent
            let title = "\(file.lastPathComponent) — \(dirName)"
            let icon = NSWorkspace.shared.icon(forFile: file.path)
            icon.size = NSSize(width: 16, height: 16)
            return (title, icon)
        } else {
            let title = entry.directory.lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: entry.directory.path)
            icon.size = NSSize(width: 16, height: 16)
            return (title, icon)
        }
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        onNavigate?(sender.tag)
    }
}
