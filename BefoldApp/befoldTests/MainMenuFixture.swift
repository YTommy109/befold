import AppKit
@testable import befold
import Foundation

/// メインメニューを入力とするテスト(`MainMenuBuilderTests` / `MenuShortcutCatalogTests`)で
/// 共有する組み立てフィクスチャ。
///
/// - `NSMenu.delegate` は weak のため、スタブ delegate はフィクスチャが強参照で保持する
///   (build() 呼び出し中だけの一時インスタンスだと、代入直後に解放され delegate が nil に化ける)。
/// - 1 テスト内でメニューを複数回参照しても、`MainMenuBuilder.build` のフルメニュー構築を
///   繰り返さないようメモ化する。Swift Testing はテストごとにスイートを再生成するため、
///   キャッシュの寿命は 1 テストに閉じる。
/// - `MainActor` 隔離のテストからのみ参照するため `Sendable` 制約は不要。
@MainActor
final class MainMenuFixture {
    final class StubMenuDelegate: NSObject, NSMenuDelegate {}

    let recentMenuDelegate: NSMenuDelegate
    let bookmarksMenuDelegate: NSMenuDelegate
    /// 呼び出し側で「その delegate が実際に設定されたか」を識別したいケースがあるため、
    /// 生成時に差し替えられるようにしている。
    let recentRepositoriesMenuDelegate: NSMenuDelegate

    private var cachedMenu: NSMenu?

    init(
        recentMenuDelegate: NSMenuDelegate = StubMenuDelegate(),
        bookmarksMenuDelegate: NSMenuDelegate = StubMenuDelegate(),
        recentRepositoriesMenuDelegate: NSMenuDelegate = StubMenuDelegate()
    ) {
        self.recentMenuDelegate = recentMenuDelegate
        self.bookmarksMenuDelegate = bookmarksMenuDelegate
        self.recentRepositoriesMenuDelegate = recentRepositoriesMenuDelegate
    }

    func menu() -> NSMenu {
        if let cachedMenu { return cachedMenu }
        // swift test のプロセスでは NSApp が未初期化のため、
        // MainMenuBuilder が参照する前に NSApplication.shared で初期化する。
        _ = NSApplication.shared
        let menu = MainMenuBuilder.build(
            openAction: #selector(AppDelegate.showOpenPanel),
            helpActions: MainMenuHelpActions(
                visitWebsite: #selector(AppDelegate.openHelp(_:)),
                featureOverview: #selector(AppDelegate.showFeatureOverview(_:)),
                keyboardShortcuts: #selector(AppDelegate.showKeyboardShortcuts(_:)),
                aiIntegration: #selector(AppDelegate.showAIIntegration(_:)),
                ossAcknowledgements: #selector(AppDelegate.showOSSLicenses(_:))
            ),
            recentMenuDelegate: recentMenuDelegate,
            bookmarksMenuDelegate: bookmarksMenuDelegate,
            recentRepositoriesMenuDelegate: recentRepositoriesMenuDelegate
        )
        cachedMenu = menu
        return menu
    }

    /// メニュータイトルは実行環境の言語で解決されるため、
    /// テストも Localizable.xcstrings 経由で期待値を得る。
    func localizedTitle(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .l10n)
    }

    func submenu(titledKey key: String.LocalizationValue) -> NSMenu? {
        let title = localizedTitle(key)
        return menu().items.first { $0.submenu?.title == title }?.submenu
    }
}
