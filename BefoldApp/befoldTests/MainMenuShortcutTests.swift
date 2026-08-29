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

/// メニューの**有効判定**が能力どおりに出ること。
/// `/menu-audit`（実行中のアプリを AX でダンプする）はこの環境では
/// assistive access が無く走らせられないため、`validateMenuItem` が使うのと
/// 同じ判定関数（`ViewerMenuValidator`）へ実際のメニュー項目を通して測る。
@Suite
@MainActor
struct ViewMenuValidationTests {
    /// 実際に構築した View メニューから、そのアクションの項目を引く。
    private func viewMenuItems(action: Selector) throws -> [NSMenuItem] {
        let view = try #require(MainMenuBuilder.makeViewMenuItem().submenu)
        return view.items.filter { $0.action == action }
    }

    /// 判定に要る値だけを持つスタブ（`ViewerMenuValidatorTests` のものは private）。
    private final class StubSource: ViewerMenuValidationSource {
        var capabilities: ViewerCapabilities = .none
        var isSourceMode = false
        var showLineNumbers = false
        var isBookmarked = false
        var canGoBack = false
        var canGoForward = false
        var effectiveDisplayMode: ViewerDisplayMode = .rendered
        var isDiffLayoutSideBySide = false
    }

    /// PDF を見ている状態 / それ以外（markdown 相当）を見ている状態。
    private func source(rotatable: Bool) -> StubSource {
        let stub = StubSource()
        stub.capabilities = ViewerCapabilities(
            isPresentingDocument: true,
            isRejected: false,
            isRenderable: true,
            isBinaryContent: rotatable,
            showsCodeContent: false,
            supportsSourceMode: !rotatable,
            supportsDiffDisplay: false,
            supportsRotation: rotatable,
            gitDiffAvailability: .undetermined,
            isDirectHTMLMode: false,
            isDocumentJumpEnabled: false
        )
        return stub
    }

    @Test("回転の項目は PDF のときだけ有効になる")
    func rotationItemsFollowTheCapability() throws {
        let items = try viewMenuItems(action: #selector(ViewerWindowController.rotateDocument(_:)))
        #expect(items.count == 2)

        for item in items {
            #expect(ViewerMenuValidator.validate(item, source: source(rotatable: true)))
            #expect(!ViewerMenuValidator.validate(item, source: source(rotatable: false)))
        }
    }

    /// 回転を足したことで、ズーム側の有効判定が巻き添えで変わっていないこと。
    @Test("ズームの項目は種別によらず有効のまま")
    func zoomItemsStayEnabled() throws {
        for action in [
            #selector(ViewerWindowController.zoomIn(_:)),
            #selector(ViewerWindowController.zoomOut(_:)),
            #selector(ViewerWindowController.resetZoom(_:)),
        ] {
            for item in try viewMenuItems(action: action) {
                #expect(ViewerMenuValidator.validate(item, source: source(rotatable: true)))
                #expect(ViewerMenuValidator.validate(item, source: source(rotatable: false)))
            }
        }
    }
}
