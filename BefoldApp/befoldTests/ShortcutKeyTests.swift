import AppKit
@testable import befold
import SwiftUI
import Testing

/// キー表記の組み立て(TASK-503)。修飾キーの並び順を知っているのはこの型だけなので、
/// メニュー由来・非メニュー由来のどちらの経路も同じ結果になることをここで測る。
@Suite
@MainActor
struct ShortcutKeyTests {
    @Test("修飾キーは ⌃⌥⇧⌘ の順に並ぶ")
    func modifierOrder() {
        let key = ShortcutKey(modifiers: [.command, .shift, .option, .control], key: "K")

        #expect(key.displayName == "⌃⌥⇧⌘K")
    }

    @Test("メニュー項目から作った表記が従来と一致する")
    func fromMenuItem() {
        let item = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "z")
        item.keyEquivalentModifierMask = [.command, .shift]

        #expect(ShortcutKey(menuItem: item).displayName == "⇧⌘Z")
        #expect(MenuShortcutCatalog.keyDisplay(of: item) == "⇧⌘Z")
    }

    @Test("SwiftUI のキーは記号へ置き換える")
    func fromKeyEquivalent() {
        #expect(ShortcutKey(key: .upArrow).displayName == "↑")
        #expect(ShortcutKey(key: .delete).displayName == "Delete")
        #expect(ShortcutKey(key: .escape).displayName == "Esc")
        #expect(ShortcutKey(key: .return, modifiers: [.command, .shift]).displayName == "⇧⌘Return")
        #expect(ShortcutKey(key: "j").displayName == "J")
    }

    @Test("ビューアの KeyboardEvent.key は記号へ置き換える")
    func fromViewerKey() {
        #expect(ShortcutKey(viewerKey: " ", shift: false).displayName == "Space")
        #expect(ShortcutKey(viewerKey: " ", shift: true).displayName == "⇧Space")
        #expect(ShortcutKey(viewerKey: "ArrowDown", shift: false).displayName == "↓")
        #expect(ShortcutKey(viewerKey: "Escape", shift: false).displayName == "Esc")
        #expect(ShortcutKey(viewerKey: "j", shift: true).displayName == "⇧J")
    }
}
