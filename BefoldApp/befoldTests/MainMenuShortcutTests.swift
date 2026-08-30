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
}

/// メニューの**有効判定**が能力どおりに出ること。
/// `/menu-audit`（実行中のアプリを AX でダンプする）はこの環境では assistive access が
/// 無く走らせられないため、`validateMenuItem` が使うのと同じ判定関数
/// （`ViewerMenuValidator`）へ実際のメニュー項目を通して測る。
@Suite
@MainActor
struct ViewMenuValidationTests {
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
    private func source(binary: Bool) -> StubSource {
        let stub = StubSource()
        stub.capabilities = ViewerCapabilities(
            isPresentingDocument: true,
            isRejected: false,
            isRenderable: true,
            isBinaryContent: binary,
            showsCodeContent: false,
            supportsSourceMode: !binary,
            supportsDiffDisplay: false,
            supportsRotation: binary,
            // markdown も PDF も検索できる（PDF は TASK-570 で開いた）。
            supportsFind: true,
            gitDiffAvailability: .undetermined,
            isDirectHTMLMode: false,
            isDocumentJumpEnabled: false
        )
        return stub
    }

    /// 回転はメニューに置かない（PDF の右上に重ねたコントロールが持つ）。
    /// メニューへ戻すと、種別に依存する項目がメニュー構築側へ増える。
    @Test("View メニューに回転の項目は無い")
    func viewMenuHasNoRotationItems() throws {
        let view = try #require(MainMenuBuilder.makeViewMenuItem().submenu)

        let titles = view.items.map(\.title)
        #expect(!titles.contains { $0.contains("回転") || $0.lowercased().contains("rotate") })
    }

    /// ズームの有効判定が種別で変わらないこと（回転を外した巻き添えが無い）。
    @Test("ズームの項目は種別によらず有効のまま")
    func zoomItemsStayEnabled() throws {
        let view = try #require(MainMenuBuilder.makeViewMenuItem().submenu)
        let zoomActions = [
            #selector(ViewerWindowController.zoomIn(_:)),
            #selector(ViewerWindowController.zoomOut(_:)),
            #selector(ViewerWindowController.resetZoom(_:)),
        ]

        for item in view.items where item.action.map({ zoomActions.contains($0) }) == true {
            #expect(ViewerMenuValidator.validate(item, source: source(binary: true)))
            #expect(ViewerMenuValidator.validate(item, source: source(binary: false)))
        }
    }
}
