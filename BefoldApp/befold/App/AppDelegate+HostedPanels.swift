import AppKit

/// 単一インスタンスのパネルウィンドウ(About・設定・Help 配下)の生成と開閉。
/// AppDelegate 本体が肥大化しないよう extension に分ける。
extension AppDelegate {
    /// 単一インスタンスのパネルを開閉する。初回だけ生成し、以降は保持したものを使う。
    func togglePanel(_ panel: HostedPanel) {
        let controller = hostedPanels[panel] ?? makePanelController(panel)
        hostedPanels[panel] = controller
        controller.toggle()
    }

    /// パネルごとの差分(中身のビュー・タイトル・サイズ・リサイズ可否)はここだけに置く。
    private func makePanelController(_ panel: HostedPanel) -> HostedPanelWindowController {
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
                rootView: CodeFontSettingsView(
                    preference: stores.codeFontPreference,
                    onChange: { [weak windowManager] in windowManager?.applyCodeFontToAllWindows() }
                ),
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
