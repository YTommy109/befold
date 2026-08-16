@testable import befold
import Testing

/// ビューア内のキー操作の一覧(TASK-503)。
///
/// 割り当ての実体は JavaScript 側にあるため、実装との突合は jest 側の
/// `viewerShortcutCatalog.test.js` が行う(このファイルをパースして
/// `resolveScrollKey` / `resolveFindCloseKey` に通す)。
///
/// ここで件数を固定しているのは、**両側が同じ列を数えていることを保証するため**。
/// jest 側のパーサがリテラル形式の変更で 0 件になっても、あちらは 0 件を検出して
/// 失敗する。こちらは「一覧に載せるつもりの件数」を独立に押さえる。
@Suite
struct ViewerShortcutCatalogTests {
    /// jest 側 `EXPECTED_VIEWER_SHORTCUT_COUNT` と同じ値。片方だけ増やすと落ちる。
    private static let expectedItemCount = 7

    @Test("宣言している件数")
    func itemCount() {
        #expect(ViewerShortcutCatalog.items.count == Self.expectedItemCount)
    }

    @Test("表示はキー定義から導かれる")
    func displayComesFromTheKeyDeclaration() {
        let entries = ViewerShortcutCatalog.section.entries

        #expect(entries.count == ViewerShortcutCatalog.items.count)
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
