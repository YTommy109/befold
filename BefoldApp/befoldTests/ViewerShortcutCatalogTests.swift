@testable import befold
import Testing

/// ビューア内のキー操作の一覧(TASK-503)。
///
/// 割り当ての実体は JavaScript 側にあるため、実装との突合は jest 側の
/// `viewerShortcutCatalog.test.js` が行う(このファイルをパースして
/// `resolveScrollKey` / `resolveBarCloseKey` / `resolveJumpNavigationKey` に通す)。
///
/// ここで件数を固定しているのは、**両側が同じ列を数えていることを保証するため**。
/// jest 側のパーサがリテラル形式の変更で 0 件になっても、あちらは 0 件を検出して
/// 失敗する。こちらは「一覧に載せるつもりの件数」を独立に押さえる。
@Suite
struct ViewerShortcutCatalogTests {
    /// jest 側 `EXPECTED_SCROLL_COUNT` / `EXPECTED_JUMP_COUNT` と同じ値。片方だけ増やすと落ちる。
    private static let expectedScrollCount = 6
    private static let expectedJumpCount = 3

    @Test("宣言している件数")
    func itemCount() {
        #expect(ViewerShortcutCatalog.scrollItems.count == Self.expectedScrollCount)
        #expect(ViewerShortcutCatalog.documentJumpItems.count == Self.expectedJumpCount)
        #expect(ViewerShortcutCatalog.items.count == Self.expectedScrollCount + Self.expectedJumpCount)
    }

    /// ゲート閉の一覧(Esc を「検索バーを閉じる」とだけ説明する版)は、ゲート撤去
    /// (TASK-485.16)で使われなくなったため削除した。残る担保は「Esc の説明が 1 行で、
    /// 両方のバーを閉じる側になっていること」。
    @Test("Esc の説明は 1 行で、検索バーとジャンプバーの両方を閉じる側を指す")
    func escapeDescribesClosingEitherBar() {
        let escapeItems = ViewerShortcutCatalog.items.filter { $0.jsKeys == ["Escape"] }

        // 併記すると Esc が 2 行に増えて一覧が実装と食い違う。
        #expect(escapeItems.count == 1)
        #expect(escapeItems.first?.expects == .barClose)
        #expect(ViewerShortcutCatalog.items.filter { $0.jsKeys == ["Enter"] }.map(\.shift) == [false, true])
    }

    @Test("表示はキー定義から導かれる")
    func displayComesFromTheKeyDeclaration() {
        let entries = ViewerShortcutCatalog.section.entries

        #expect(entries.count == ViewerShortcutCatalog.items.count)
        #expect(entries.contains { $0.key == "Return" })
        #expect(entries.contains { $0.key == "⇧Return" })
        #expect(entries.contains { $0.key == "Space" })
        #expect(entries.contains { $0.key == "⇧Space" })
        #expect(entries.contains { $0.key == "↓ / J" })
        #expect(entries.contains { $0.key == "⇧↑ / ⇧K" })
        #expect(entries.contains { $0.key == "Esc" })
    }

    @Test("期待値は JS 側の解決結果と同じ語彙で書かれている")
    func expectationsAreDistinct() {
        let expectations = ViewerShortcutCatalog.items.map(\.expects.rawValue)

        // 同じ期待値を 2 行で宣言していないこと(重複は突合の取りこぼしを生む)。
        #expect(Set(expectations).count == expectations.count)
    }
}
