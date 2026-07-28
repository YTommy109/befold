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
    private let notificationCenter: NotificationCenter
    private var panel: NSPanel?

    /// パネルが表示中かどうか。表示状態を外部(テスト)から観測するためのシーム。
    var isPresented: Bool {
        panel != nil
    }

    /// - Parameters:
    ///   - makeEnvironment: 候補源。パネルを開くたびに作り直し、その時点の索引と
    ///     現在開いているファイルを反映させる。組み立てられなければ nil を返し、パネルは開かない。
    ///   - onOpen: 決定した URL の開き先。
    ///   - notificationCenter: 非アクティブ化通知(`didResignActiveNotification`)の購読先。
    ///     既定は `.default`(本番)。テストは独自 center を注入して通知を直接ポストできる。
    init(
        makeEnvironment: @escaping () -> (any QuickOpenEnvironment)?,
        onOpen: @escaping (URL) -> Void,
        notificationCenter: NotificationCenter = .default
    ) {
        self.makeEnvironment = makeEnvironment
        self.onOpen = onOpen
        self.notificationCenter = notificationCenter
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
        // 非アクティブ化の購読は present 中だけ有効にする。閉じるときに必ず解除して、
        // 未表示時にアプリが非アクティブ化しても余計な dismiss が走らないようにする。
        notificationCenter.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        // isReleasedWhenClosed=false のため close() は安全で、AppKit のウィンドウ終了経路
        // (windowWillClose 通知・ウィンドウリスト登録解除)に正しく乗る。
        panel?.close()
        panel = nil
    }

    /// 他アプリへ切り替えて befold が非アクティブ化したら閉じる(Spotlight と同じ振る舞い)。
    /// `.nonactivatingPanel` のフローティングパネルはアプリ非アクティブ化をまたいで残るため、
    /// `windowDidResignKey` だけでは他アプリ切替時に閉じない。それをここで補う。
    @objc private func handleAppDidResignActive() {
        dismiss()
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
        let hosting = NSHostingController(
            rootView: QuickOpenView(model: model) { [weak self] in self?.dismiss() }
        )
        // これが無いとパネルは生成時の高さのまま固定され、候補リストが
        // 一切見えなくなる(入力欄だけのパネルになる)。preferredContentSize を
        // SwiftUI の要求サイズへ追従させ、NSWindow 側にそれを拾わせる。
        hosting.sizingOptions = [.preferredContentSize]

        // borderless にしてタイトルバーとその境界線(グレーの横線)を無くす。ただし素の
        // borderless NSPanel は key になれず TextField にフォーカスが移らないため、
        // canBecomeKey を上書きした専用サブクラスを使う(Spotlight 型パネルの定石)。
        let panel = KeyableBorderlessPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.delegate = self

        self.panel = panel
        // 他アプリへ切り替えて befold が非アクティブ化したら閉じる。present 中だけ購読する。
        notificationCenter.addObserver(
            self, selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil
        )
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    /// キーウィンドウ(無ければメイン画面)の上端寄りに水平中央で置く。
    private func position(_ panel: NSPanel) {
        let reference = NSApp.keyWindow?.frame ?? NSScreen.main?.visibleFrame
        guard let reference else { return }
        // layoutIfNeeded() だけでは NSHostingController の preferredContentSize が
        // まだパネルへ伝わっておらず frame.size がほぼ空のまま原点計算に使われる。
        // SwiftUI 側の要求サイズを先にパネルへ確定させてから原点を求める。
        panel.layoutIfNeeded()
        if let contentView = panel.contentViewController?.view {
            panel.setContentSize(contentView.fittingSize)
        }
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

/// borderless でもキーウィンドウになれる `NSPanel`。
/// 素の borderless ウィンドウは `canBecomeKey` が false のため、入力欄にフォーカスが
/// 移らず文字を打てない。タイトルバー(とその境界線)を持たずに検索フィールドへ
/// キー入力を受けるため、`canBecomeKey` を true に上書きする。
private final class KeyableBorderlessPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}
