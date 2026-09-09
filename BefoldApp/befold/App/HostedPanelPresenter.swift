import AppKit

/// 単一インスタンスのパネルウィンドウ(About・設定・Help 配下)の生成と開閉。
///
/// パネルごとの差分(中身のビュー・タイトル・サイズ・リサイズ可否)と、生成済み
/// コントローラのレジストリをここだけが持つ。アプリのライフサイクルとは無関係なので
/// `AppDelegate` の extension ではなく独立した型に置く(TASK-604.3)。
/// `AppDelegate` の `@objc` アクションは `toggle(_:)` へ転送するだけになる。
@MainActor
final class HostedPanelPresenter {
    private let stores: AppStores
    /// パネルの設定変更を全ウィンドウへ反映するために使う。所有者は AppDelegate なので weak。
    private weak var windowManager: ViewerWindowManager?
    /// 初回のトグルで生成し、以降は同じインスタンスを使い回す。
    private var controllers: [HostedPanel: HostedPanelWindowController] = [:]

    init(stores: AppStores, windowManager: ViewerWindowManager) {
        self.stores = stores
        self.windowManager = windowManager
    }

    /// 単一インスタンスのパネルを開閉する。初回だけ生成し、以降は保持したものを使う。
    func toggle(_ panel: HostedPanel) {
        let controller = controllers[panel] ?? makeController(panel)
        controllers[panel] = controller
        controller.toggle()
    }

    /// 設定パネルの中身。変更の反映先が全ウィンドウなので、他のパネルと違って
    /// `windowManager` への配線を持つ。
    private func makeSettingsView() -> SettingsView {
        SettingsView(
            preference: stores.codeFontPreference,
            onChange: { [weak windowManager] in windowManager?.display.applyCodeFontToAllWindows() },
            numberPreference: stores.csvNumberFormatPreference,
            onNumberChange: { [weak windowManager] in
                windowManager?.display.applyCsvNumberFormatToAllWindows()
            }
        )
    }

    /// パネルごとの差分(中身のビュー・タイトル・サイズ・リサイズ可否)はここだけに置く。
    private func makeController(_ panel: HostedPanel) -> HostedPanelWindowController {
        switch panel {
        case .about:
            HostedPanelWindowController(
                rootView: AboutView(),
                title: String(localized: "about.windowTitle", bundle: .l10n),
                resizable: false,
                contentSize: NSSize(width: 480, height: 340),
                minSize: NSSize(width: 360, height: 260)
            )
        case .settings:
            HostedPanelWindowController(
                rootView: makeSettingsView(),
                title: String(localized: "settings.windowTitle", bundle: .l10n),
                resizable: false
            )
        case .featureOverview:
            HostedPanelWindowController(
                rootView: FeatureOverviewView(),
                title: String(localized: "featureOverview.windowTitle", bundle: .l10n),
                resizable: true,
                contentSize: NSSize(width: 480, height: 420),
                minSize: NSSize(width: 400, height: 320)
            )
        case .keyboardShortcuts:
            HostedPanelWindowController(
                rootView: KeyboardShortcutsView(),
                title: String(localized: "keyboardShortcuts.windowTitle", bundle: .l10n),
                resizable: true,
                contentSize: NSSize(width: 480, height: 520),
                minSize: NSSize(width: 400, height: 320)
            )
        case .aiIntegration:
            HostedPanelWindowController(
                rootView: AIIntegrationView(),
                title: String(localized: "aiIntegration.windowTitle", bundle: .l10n),
                resizable: true,
                contentSize: NSSize(width: 520, height: 560),
                minSize: NSSize(width: 440, height: 320)
            )
        case .ossLicenses:
            HostedPanelWindowController(
                rootView: OSSLicensesView(),
                title: String(localized: "ossLicenses.windowTitle", bundle: .l10n),
                resizable: true,
                contentSize: NSSize(width: 560, height: 560),
                minSize: NSSize(width: 420, height: 320)
            )
        }
    }
}
