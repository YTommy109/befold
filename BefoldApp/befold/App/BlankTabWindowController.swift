import AppKit
import SwiftUI

/// 空タブの表示と閉じる通知。文書を選ぶまでレンダラ・ファイル監視は生成しない。
final class BlankTabWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: (BlankTabWindowController) -> Void
    private(set) var isClosed = false

    init(onClose: @escaping (BlankTabWindowController) -> Void) {
        self.onClose = onClose
        let window = ViewerWindowChrome.makeWindow(fileURL: nil)
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: BlankTabView())
        DocumentFileDropView.install(on: window)
        ViewerWindowChrome.applyInitialFrame(nil, to: window, kind: .viewer, isOccupied: { _ in false })
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        onClose(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window else { return }
        ViewerTabGrouping.syncWindowsMenuMembership(among: ViewerTabGrouping.tabWindows(of: window))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

private struct BlankTabView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(String(localized: "tab.empty.title", bundle: .l10n))
                .font(.title2)
            Text(String(localized: "tab.empty.detail", bundle: .l10n))
                .foregroundStyle(.secondary)
            Button(String(localized: "menu.file.open", bundle: .l10n)) {
                NSApp.sendAction(#selector(AppDelegate.showOpenPanel), to: nil, from: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
