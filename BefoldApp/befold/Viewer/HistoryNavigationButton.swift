import AppKit
import SwiftUI

// MARK: - HistoryNavigationButton

final class HistoryButtonView: NSButton {
    weak var coordinator: HistoryNavigationButton.Coordinator?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            coordinator?.showMenu(from: self)
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
            coordinator?.primaryAction()
        } else if !mouseUp {
            coordinator?.showMenu(from: self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        coordinator?.showMenu(from: self)
    }
}

struct HistoryNavigationButton: NSViewRepresentable {
    let systemImage: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let entries: [HistoryEntry]
    let primaryOffset: Int
    let onNavigate: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HistoryButtonView {
        let button = HistoryButtonView(frame: .zero)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.coordinator = context.coordinator
        configure(button)
        return button
    }

    func updateNSView(_ button: HistoryButtonView, context: Context) {
        context.coordinator.parent = self
        configure(button)
    }

    private func configure(_ button: HistoryButtonView) {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        button.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: accessibilityLabel
        )?.withSymbolConfiguration(config)
        button.isEnabled = isEnabled
        button.contentTintColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: HistoryNavigationButton

        init(parent: HistoryNavigationButton) {
            self.parent = parent
        }

        func primaryAction() {
            parent.onNavigate(parent.primaryOffset)
        }

        func showMenu(from view: NSView) {
            guard !parent.entries.isEmpty else { return }
            let menu = NSMenu()
            let direction = parent.primaryOffset < 0 ? -1 : 1
            for (index, entry) in parent.entries.enumerated() {
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
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 2), in: view)
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
            parent.onNavigate(sender.tag)
        }
    }
}
