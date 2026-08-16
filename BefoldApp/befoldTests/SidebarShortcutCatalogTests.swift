@testable import befold
import SwiftUI
import Testing

/// Help の一覧に載せるサイドバーのキーと、実際のディスパッチ
/// (`SidebarKeyAction.action`) がずれていないこと(TASK-503)。
///
/// **双方向で縛るのが要点。** 健全性(載せたキーが実際に反応する)だけだと、
/// ディスパッチにキーを足したときに一覧が黙って古くなる。完全性(反応するキーは
/// すべて載っている)を対にして、どちらの向きのずれも落ちるようにする。
@Suite
struct SidebarShortcutCatalogTests {
    /// 総当たりに使う候補キー。ディスパッチが見ている種類(英字・矢印・return・delete)を
    /// 網羅する。ここに無いキーを `SidebarKeyAction` が拾い始めた場合は
    /// `unlistedKeysAreIgnored` では検出できないため、候補もあわせて広げること。
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

    private static let candidateModifiers: [(EventModifiers, String)] = [
        ([], "なし"), (.command, "⌘"), (.shift, "⇧"), ([.command, .shift], "⌘⇧"), (.option, "⌥"),
    ]

    /// 選択行・表示モードの組み合わせ。どれか 1 つでも反応すれば「そのキーは使われている」。
    private static let contexts: [(SidebarKeyAction.Target?, SidebarLayoutMode)] = [
        (SidebarKeyAction.Target(kind: .file), .drillDown),
        (SidebarKeyAction.Target(kind: .file), .tree),
        (SidebarKeyAction.Target(kind: .folder), .drillDown),
        (SidebarKeyAction.Target(kind: .folder), .tree),
        (SidebarKeyAction.Target(kind: .folder, isExpanded: true), .tree),
        (nil, .drillDown),
        (nil, .tree),
    ]

    /// 状況ごとの解決結果。キーの「効き方」をこの並びで表す。
    private static func outcomes(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> [SidebarKeyAction] {
        contexts.map { target, mode in
            SidebarKeyAction.action(key: key, modifiers: modifiers, target: target, mode: mode)
        }
    }

    private static func reacts(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> Bool {
        outcomes(key, modifiers).contains { $0 != .ignored }
    }

    @Test("一覧に載せたキーはすべて実際に何かの動作へ解決される")
    func listedKeysDispatch() {
        for item in SidebarShortcutCatalog.items {
            for key in item.keys {
                #expect(
                    Self.reacts(key.key, key.modifiers),
                    "一覧の \(key.display.displayName) がどの状況でも .ignored になっている"
                )
            }
        }
    }

    @Test("動作へ解決されるキーはすべて一覧に載っている")
    func unlistedKeysAreIgnored() {
        for (key, keyName) in Self.candidateKeys {
            // 同じキーで一覧に載っている組み合わせの「効き方」。
            let listedOutcomes = SidebarShortcutCatalog.items
                .flatMap(\.keys)
                .filter { $0.display.key == ShortcutKey(key: key).key }
                .map { Self.outcomes($0.key, $0.modifiers) }

            for (modifiers, modifierName) in Self.candidateModifiers where Self.reacts(key, modifiers) {
                // ディスパッチが条件にしている修飾キーは ⌘ だけで、⇧ / ⌥ を足しても
                // 結果は変わらない(⌘⇧↑ は ⌘↑ と同じ)。効き方が一覧のどれかと同じなら、
                // その組み合わせは既に説明されている。**新しい効き方だけ**を必須にする。
                #expect(
                    listedOutcomes.contains(Self.outcomes(key, modifiers)),
                    "\(modifierName) + \(keyName) が一覧のどの行とも違う動作をするのに Help に無い"
                )
            }
        }
    }

    @Test("表示は実装で使うキー定義から導かれる")
    func displayComesFromTheDispatchedKey() {
        let entries = SidebarShortcutCatalog.section.entries

        #expect(entries.count == SidebarShortcutCatalog.items.count)
        #expect(entries.contains { $0.key == "↓ / J" })
        #expect(entries.contains { $0.key == "⌘↑ / Delete" })
        #expect(entries.contains { $0.key == "⇧⌘Return" })
    }
}
