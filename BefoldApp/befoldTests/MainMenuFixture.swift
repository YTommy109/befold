import AppKit
@testable import befold
import Foundation

/// メインメニューを入力とするテスト(`MainMenuBuilderTests` / `MenuShortcutCatalogTests`)で
/// 共有する組み立てフィクスチャ。
///
/// - `NSMenu.delegate` は weak のため、スタブ delegate はフィクスチャが強参照で保持する
///   (build() 呼び出し中だけの一時インスタンスだと、代入直後に解放され delegate が nil に化ける)。
/// - **組み立てた `NSMenu` をフィクスチャに保持しない**(メモ化しない)。`@MainActor` な
///   クラスでも `deinit` は非隔離で、Swift Testing がスイート値を破棄するスレッドは
///   メインとは限らない。実測(TASK-525): メニュー系 2 スイート 23 テストの実行で
///   フィクスチャの `deinit` が 36 回すべて非メインスレッドで走った。フィクスチャが
///   メニュー木を握っていると、そこから `NSMenu.dealloc` が並行に走り、AppKit が
///   メニュー名の登録に使うプロセスグローバルな `NSPointerArray` が壊れて
///   `removePointerAtIndex: ... beyond bounds` で abort する。
///   保持しなければメニューは `@MainActor` なテスト本体のローカル変数として
///   メインスレッド上で解放されるため、この経路が構造的に消える。
/// - `MainActor` 隔離のテストからのみ参照するため `Sendable` 制約は不要。
@MainActor
final class MainMenuFixture {
    final class StubMenuDelegate: NSObject, NSMenuDelegate {}

    let recentMenuDelegate: NSMenuDelegate
    let bookmarksMenuDelegate: NSMenuDelegate
    /// 呼び出し側で「その delegate が実際に設定されたか」を識別したいケースがあるため、
    /// 生成時に差し替えられるようにしている。
    let recentRepositoriesMenuDelegate: NSMenuDelegate
    /// 文書内ジャンプ（開発中機能）のゲート。既定は dev ビルド相当の開いた状態。
    let isDocumentJumpEnabled: Bool

    init(
        recentMenuDelegate: NSMenuDelegate = StubMenuDelegate(),
        bookmarksMenuDelegate: NSMenuDelegate = StubMenuDelegate(),
        recentRepositoriesMenuDelegate: NSMenuDelegate = StubMenuDelegate(),
        isDocumentJumpEnabled: Bool = true
    ) {
        self.recentMenuDelegate = recentMenuDelegate
        self.bookmarksMenuDelegate = bookmarksMenuDelegate
        self.recentRepositoriesMenuDelegate = recentRepositoriesMenuDelegate
        self.isDocumentJumpEnabled = isDocumentJumpEnabled
    }

    /// 呼ぶたびにフルメニューを組み立て直す。戻り値を保持するのは呼び出し側の
    /// ローカル変数だけにすること(上のメモ化しない理由を参照)。
    func menu() -> NSMenu {
        // swift test のプロセスでは NSApp が未初期化のため、
        // MainMenuBuilder が参照する前に NSApplication.shared で初期化する。
        _ = NSApplication.shared
        return MainMenuBuilder.build(
            openAction: #selector(AppDelegate.showOpenPanel),
            helpActions: MainMenuHelpActions(
                visitWebsite: #selector(AppDelegate.openHelp(_:)),
                githubIssues: #selector(AppDelegate.openGitHubIssues(_:)),
                featureOverview: #selector(AppDelegate.showFeatureOverview(_:)),
                keyboardShortcuts: #selector(AppDelegate.showKeyboardShortcuts(_:)),
                aiIntegration: #selector(AppDelegate.showAIIntegration(_:)),
                ossAcknowledgements: #selector(AppDelegate.showOSSLicenses(_:))
            ),
            dynamicMenuDelegates: MainMenuDynamicMenuDelegates(
                recent: recentMenuDelegate,
                bookmarks: bookmarksMenuDelegate,
                recentRepositories: recentRepositoriesMenuDelegate
            ),
            isDocumentJumpEnabled: isDocumentJumpEnabled
        )
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
