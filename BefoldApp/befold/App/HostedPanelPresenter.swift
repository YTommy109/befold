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
    /// パネルからファイルを開く経路。`DocumentOpener.openViewer`(開く唯一の入口)を
    /// AppDelegate が渡す。既定値は置かない——別の経路で開く書き方をコンパイルできなくする。
    private let openHandler: @MainActor (URL) -> Void
    /// 初回のトグルで生成し、以降は同じインスタンスを使い回す。
    private var controllers: [HostedPanel: HostedPanelWindowController] = [:]

    init(
        stores: AppStores,
        windowManager: ViewerWindowManager,
        openHandler: @escaping @MainActor (URL) -> Void
    ) {
        self.stores = stores
        self.windowManager = windowManager
        self.openHandler = openHandler
    }

    /// 単一インスタンスのパネルを開閉する。初回だけ生成し、以降は保持したものを使う。
    func toggle(_ panel: HostedPanel) {
        let controller = controllers[panel] ?? makeController(panel)
        controllers[panel] = controller
        controller.toggle()
    }

    /// 設定パネル。変更の反映先が全ウィンドウなので、他のパネルと違って
    /// `windowManager` への配線を持つ。
    private func makeSettingsController() -> HostedPanelWindowController {
        let view = SettingsView(
            preference: stores.codeFontPreference,
            onChange: { [weak windowManager] in windowManager?.display.applyCodeFontToAllWindows() },
            numberPreference: stores.csvNumberFormatPreference,
            onNumberChange: { [weak windowManager] in
                windowManager?.display.applyCsvNumberFormatToAllWindows()
            }
        )
        return HostedPanelWindowController(
            rootView: view,
            title: String(localized: "settings.windowTitle", bundle: .l10n),
            resizable: false
        )
    }

    /// ブックマーク管理パネル。ストアはアプリ全体で 1 個の `stores.bookmarkStore` を渡し、
    /// 開く経路は `openHandler`(`DocumentOpener`)へつなぐ。
    private func makeBookmarksController() -> HostedPanelWindowController {
        let model = BookmarkManagerModel(store: stores.bookmarkStore, open: openHandler)
        return HostedPanelWindowController(
            rootView: BookmarkManagerView(model: model),
            title: String(localized: "bookmarks.manager.windowTitle", bundle: .l10n),
            resizable: true,
            contentSize: NSSize(width: 520, height: 420),
            minSize: NSSize(width: 400, height: 300)
        )
    }

    /// パネルごとの差分(中身のビュー・タイトル・サイズ・リサイズ可否)はここだけに置く。
    /// 依存の配線を持つ 2 つ(設定・ブックマーク)は専用のビルダーへ出してある。
    private func makeController(_ panel: HostedPanel) -> HostedPanelWindowController {
        switch panel {
        case .settings:
            makeSettingsController()
        case .bookmarks:
            makeBookmarksController()
        case .about:
            HostedPanelWindowController(
                rootView: AboutView(),
                title: String(localized: "about.windowTitle", bundle: .l10n),
                resizable: false,
                contentSize: NSSize(width: 480, height: 340),
                minSize: NSSize(width: 360, height: 260)
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
