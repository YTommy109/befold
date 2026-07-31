import AppKit
@testable import befold
import Testing

/// Help > キーボードショートカット の一覧が MainMenuBuilder の定義から生成されること。
/// 一覧をビューにハードコードしていた頃はメニュー側の変更に追従できず乖離していたため、
/// ここでは「実際に組み立てたメニュー」を入力にして抽出結果を検証する。
@Suite
@MainActor
struct MenuShortcutCatalogTests {
    private final class StubMenuDelegate: NSObject, NSMenuDelegate {}

    // NSMenu.delegate は weak のため、テスト実行中は強参照を保持しておく。
    private let recentMenuDelegate = StubMenuDelegate()
    private let bookmarksMenuDelegate = StubMenuDelegate()
    private let recentRepositoriesMenuDelegate = StubMenuDelegate()

    private func buildMenu() -> NSMenu {
        // swift test のプロセスでは NSApp が未初期化のため先に生成する。
        _ = NSApplication.shared
        return MainMenuBuilder.build(
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
    }

    private func groups() -> [MenuShortcutCatalog.Group] {
        MenuShortcutCatalog.groups(from: buildMenu(), appMenuTitle: "befold")
    }

    private func localizedTitle(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .l10n)
    }

    private func entries(inGroupTitled title: String) -> [MenuShortcutCatalog.Entry] {
        groups().first { $0.title == title }?.entries ?? []
    }

    @Test("トップレベルメニューごとにグループ化される")
    func groupsFollowTopLevelMenus() {
        let titles = groups().map(\.title)

        #expect(titles == [
            "befold",
            localizedTitle("menu.file.title"),
            localizedTitle("menu.edit.title"),
            localizedTitle("menu.view.title"),
            localizedTitle("menu.window.title"),
            localizedTitle("menu.help.title"),
        ])
    }

    @Test("キー等価を持たない項目は一覧に出ない")
    func itemsWithoutKeyEquivalentAreExcluded() {
        let appEntries = entries(inGroupTitled: "befold")

        // About / Check for Updates / Install CLI はショートカット未割り当て。
        #expect(!appEntries.contains { $0.title == localizedTitle("menu.app.about") })
        #expect(!appEntries.contains { $0.title == localizedTitle("menu.app.checkForUpdates") })
        #expect(!appEntries.contains { $0.title == localizedTitle("menu.app.installCLI") })
        #expect(appEntries.contains { $0.title == localizedTitle("menu.app.quit") })
    }

    @Test("区切り線と動的サブメニューは一覧に出ない")
    func separatorsAndDynamicSubmenusAreExcluded() {
        let fileEntries = entries(inGroupTitled: localizedTitle("menu.file.title"))

        #expect(!fileEntries.contains { $0.title.isEmpty })
        #expect(!fileEntries.contains { $0.title == localizedTitle("menu.file.openRecent") })
        #expect(!fileEntries.contains { $0.title == localizedTitle("menu.file.bookmarks") })
    }

    /// 修飾キーは macOS 標準の ⌃⌥⇧⌘ 順で表記し、英字は大文字にする。
    @Test(arguments: [
        (groupKey: "menu.app.title", titleKey: "menu.app.hideOthers", key: "⌥⌘H"),
        (groupKey: "menu.edit.title", titleKey: "menu.edit.redo", key: "⇧⌘Z"),
        (groupKey: "menu.edit.title", titleKey: "menu.edit.copy", key: "⌘C"),
        (groupKey: "menu.view.title", titleKey: "menu.view.enterFullScreen", key: "⌃⌘F"),
        (groupKey: "menu.view.title", titleKey: "menu.view.showHiddenFiles", key: "⌃⌘H"),
        (groupKey: "menu.view.title", titleKey: "menu.view.goBack", key: "⌘["),
        (groupKey: "menu.file.title", titleKey: "menu.file.print", key: "⇧⌘P"),
        // 旧一覧は存在しないキー menu.help.appHelp を ⌘? として載せていた(TASK-240 で判明)。
        (groupKey: "menu.help.title", titleKey: "menu.help.visitWebsite", key: "⌘?"),
    ])
    func modifierSymbolsFollowStandardOrder(groupKey: String, titleKey: String, key: String) throws {
        // アプリメニューだけはメニュー自体にタイトルが無いため、呼び出し側が与えた名前で引く。
        let groupTitle = groupKey == "menu.app.title"
            ? "befold"
            : localizedTitle(String.LocalizationValue(groupKey))
        let entry = try #require(
            entries(inGroupTitled: groupTitle)
                .first { $0.title == localizedTitle(String.LocalizationValue(titleKey)) }
        )

        #expect(entry.key == key)
    }

    @Test("メニューに割り当てた全ショートカットが一覧に現れる")
    func everyAssignedShortcutAppears() {
        let mainMenu = buildMenu()
        let assigned = mainMenu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .filter { !$0.keyEquivalent.isEmpty }

        let listed = groups().flatMap(\.entries)
        #expect(listed.count == assigned.count)
        for item in assigned {
            #expect(listed.contains { $0.title == item.title })
        }
    }
}
