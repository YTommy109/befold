import AppKit
import SwiftUI

/// Quick Open パネル(`NSPanel`)の生存と表示位置だけを持つ。
/// 候補の決定も開く先の決定も `QuickOpenModel` より下の層で完結しており、
/// ここには判断ロジックを置かない。
@MainActor
final class QuickOpenPanelController: NSObject {
    /// 画面の高さに対するパネル上端の位置。Spotlight と同じくやや上に寄せる。
    private static let verticalPositionRatio = 0.22

    private let makeEnvironment: () -> (any QuickOpenEnvironment)?
    private let onOpen: (URL) -> Void
    private var panel: NSPanel?

    /// - Parameters:
    ///   - makeEnvironment: 候補源。パネルを開くたびに作り直し、その時点の索引と
    ///     現在開いているファイルを反映させる。組み立てられなければ nil を返し、パネルは開かない。
    ///   - onOpen: 決定した URL の開き先。
    init(makeEnvironment: @escaping () -> (any QuickOpenEnvironment)?, onOpen: @escaping (URL) -> Void) {
        self.makeEnvironment = makeEnvironment
        self.onOpen = onOpen
    }

    /// 表示中なら閉じ、そうでなければ開く(⌘P の再押下で引っ込む)。
    func toggle() {
        if panel != nil {
            dismiss()
        } else {
            present()
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Private

    private func present() {
        // 開くたびにモデルを作り直す。決定時はまずパネルを畳んでから開き、
        // 新しいウィンドウの後ろにパネルが残らないようにする。
        guard let environment = makeEnvironment() else { return }
        let model = QuickOpenModel(environment: environment) { [weak self] url in
            self?.dismiss()
            self?.onOpen(url)
        }
        // contentViewController に載せることで、候補の増減に合わせて
        // パネルの高さが SwiftUI 側の要求サイズへ追従する。
        let hosting = NSHostingController(
            rootView: QuickOpenView(model: model) { [weak self] in self?.dismiss() }
        )

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.delegate = self
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    /// キーウィンドウ(無ければメイン画面)の上端寄りに水平中央で置く。
    private func position(_ panel: NSPanel) {
        let reference = NSApp.keyWindow?.frame ?? NSScreen.main?.visibleFrame
        guard let reference else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: reference.midX - size.width / 2,
            y: reference.maxY - reference.height * Self.verticalPositionRatio - size.height
        ))
    }
}

extension QuickOpenPanelController: NSWindowDelegate {
    /// フォーカスを失ったら閉じる(Spotlight と同じ振る舞い)。
    func windowDidResignKey(_: Notification) {
        dismiss()
    }
}
