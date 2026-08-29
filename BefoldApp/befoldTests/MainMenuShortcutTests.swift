import AppKit
@testable import befold
import Testing

/// メニューのキー等価(ショートカット)に関する検証。
/// `MainMenuBuilderTests` から分けているのは、あちらが swiftlint の
/// type_body_length を超えないようにするため(既存の分割と同じ粒度)。
@Suite
@MainActor
struct MainMenuShortcutTests {
    private let fixture = MainMenuFixture()

    /// **メニュー全体**でキー等価(キー + 修飾キー)が重複していない。
    ///
    /// View メニュー内の重複検査だけだと、別のトップレベルメニューとの衝突が
    /// 素通りする（⌘R を View へ足したときに File の項目と当たっても気づけない）。
    /// ショートカットを足すときにここが落ちる形にしておく（TASK-564.5）。
    @Test("メインメニュー全体でキー等価は重複しない")
    func mainMenuShortcutsAreUniqueAcrossMenus() {
        let mainMenu = fixture.menu()

        let shortcuts = mainMenu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .filter { !$0.keyEquivalent.isEmpty }
            .map { "\($0.keyEquivalentModifierMask.rawValue):\($0.keyEquivalent)" }
        let duplicates = Dictionary(grouping: shortcuts, by: { $0 }).filter { $0.value.count > 1 }
        #expect(duplicates.isEmpty, "重複したキー等価: \(duplicates.keys.sorted())")
    }

    /// PDF の回転（⌘R / ⇧⌘R）。向きは項目のタグが運ぶ。
    @Test("View メニューの回転項目は ⌘R / ⇧⌘R で、向きをタグで運ぶ")
    func viewMenuHasRotationItems() throws {
        let view = try #require(MainMenuBuilder.makeViewMenuItem().submenu)

        let items = view.items.filter {
            $0.action == #selector(ViewerWindowController.rotateDocument(_:))
        }
        #expect(items.map(\.tag) == [90, -90])
        #expect(items.allSatisfy { $0.keyEquivalent == "r" })
        #expect(items.first?.keyEquivalentModifierMask == [.command])
        #expect(items.last?.keyEquivalentModifierMask == [.command, .shift])
    }
}
