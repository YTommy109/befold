@testable import befold
import SwiftUI
import Testing

/// Quick Open のキー割り当てと、Help の一覧が一致していること(TASK-503)。
/// サイドバーと同じく双方向で縛る。
@Suite
struct QuickOpenKeyActionTests {
    private static let candidateKeys: [(KeyEquivalent, String)] = {
        let letters = "abcdefghijklmnopqrstuvwxyz".map { (KeyEquivalent($0), String($0)) }
        let named: [(KeyEquivalent, String)] = [
            (.upArrow, "upArrow"), (.downArrow, "downArrow"),
            (.leftArrow, "leftArrow"), (.rightArrow, "rightArrow"),
            (.return, "return"), (.delete, "delete"),
            (.escape, "escape"), (.tab, "tab"), (.space, "space"),
        ]
        return letters + named
    }()

    @Test("キーごとの動作")
    func actions() {
        #expect(QuickOpenKeyAction.action(for: .upArrow) == .moveSelection(offset: -1))
        #expect(QuickOpenKeyAction.action(for: .downArrow) == .moveSelection(offset: 1))
        #expect(QuickOpenKeyAction.action(for: .tab) == .completePath)
        #expect(QuickOpenKeyAction.action(for: .return) == .commit)
        #expect(QuickOpenKeyAction.action(for: .escape) == .dismiss)
        #expect(QuickOpenKeyAction.action(for: "a") == nil)
    }

    @Test("一覧に載せたキーはすべて動作を持つ")
    func listedKeysHaveActions() {
        for item in QuickOpenShortcutCatalog.items {
            for key in item.keys {
                #expect(
                    QuickOpenKeyAction.action(for: key) != nil,
                    "一覧の \(ShortcutKey(key: key).displayName) に対応する動作が無い"
                )
            }
        }
    }

    @Test("動作を持つキーはすべて一覧に載っている")
    func everyHandledKeyIsListed() {
        let listed = Set(QuickOpenShortcutCatalog.items.flatMap(\.keys).map { ShortcutKey(key: $0) })

        for (key, name) in Self.candidateKeys where QuickOpenKeyAction.action(for: key) != nil {
            #expect(listed.contains(ShortcutKey(key: key)), "\(name) が動作するのに Help の一覧に無い")
        }
    }

    @Test("表示はキー定義から導かれる")
    func displayComesFromTheKey() {
        let entries = QuickOpenShortcutCatalog.section.entries

        #expect(entries.count == QuickOpenShortcutCatalog.items.count)
        #expect(entries.contains { $0.key == "↓ / ↑" })
        #expect(entries.contains { $0.key == "Esc" })
    }
}
