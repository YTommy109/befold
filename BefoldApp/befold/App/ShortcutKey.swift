import AppKit
import SwiftUI

/// ショートカット 1 つ分のキー表記。修飾キーの並び順(⌃⌥⇧⌘)を知っているのはこの型だけで、
/// メニュー由来・非メニュー由来のどちらの一覧も表記の組み立てをここへ集約する(TASK-503)。
///
/// 表示用の文字列を各所で組み立てないのは、`BookmarkShortcut` が
/// `displayName` をキー定義から導いているのと同じ理由(定義と表記の二重管理を作らない)。
struct ShortcutKey: Hashable {
    /// 修飾キー。`allCases` の並びがそのまま表記順になる。
    enum Modifier: CaseIterable {
        case control, option, shift, command

        var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    let modifiers: Set<Modifier>
    /// 修飾キーを除いた中核の表記(例: "J" / "↑" / "Space")。
    let key: String

    var displayName: String {
        Modifier.allCases.filter { modifiers.contains($0) }.map(\.symbol).joined() + key
    }

    /// 既定値を持たせないのは、`ShortcutKey(key: "j")` が
    /// `KeyEquivalent` 版ではなくこちら(String 版)へ解決されてしまうため。
    init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// メニュー項目のキー等価から作る。
    init(menuItem: NSMenuItem) {
        let mask = menuItem.keyEquivalentModifierMask
        var modifiers: Set<Modifier> = []
        if mask.contains(.control) { modifiers.insert(.control) }
        if mask.contains(.option) { modifiers.insert(.option) }
        if mask.contains(.shift) { modifiers.insert(.shift) }
        if mask.contains(.command) { modifiers.insert(.command) }
        self.init(modifiers: modifiers, key: menuItem.keyEquivalent.uppercased())
    }

    /// SwiftUI の `.onKeyPress` 系が受けるキーから作る(サイドバー・Quick Open)。
    init(key: KeyEquivalent, modifiers eventModifiers: EventModifiers = []) {
        var modifiers: Set<Modifier> = []
        if eventModifiers.contains(.control) { modifiers.insert(.control) }
        if eventModifiers.contains(.option) { modifiers.insert(.option) }
        if eventModifiers.contains(.shift) { modifiers.insert(.shift) }
        if eventModifiers.contains(.command) { modifiers.insert(.command) }
        self.init(modifiers: modifiers, key: Self.display(of: key))
    }

    /// ビューア(WKWebView)側の KeyboardEvent.key から作る。
    ///
    /// `viewer-src/keyboard.js` が受け取る値をそのまま渡すため、表記はキー定義から導かれ、
    /// 一覧のために別の文字列を持たずに済む。
    init(viewerKey: String, shift: Bool) {
        self.init(modifiers: shift ? [.shift] : [], key: Self.display(ofViewerKey: viewerKey))
    }

    private static func display(of key: KeyEquivalent) -> String {
        switch key {
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .return: "Return"
        case .delete: "Delete"
        case .escape: "Esc"
        case .tab: "Tab"
        case .space: "Space"
        default: String(key.character).uppercased()
        }
    }

    private static func display(ofViewerKey key: String) -> String {
        switch key {
        case " ": "Space"
        case "ArrowUp": "↑"
        case "ArrowDown": "↓"
        case "ArrowLeft": "←"
        case "ArrowRight": "→"
        case "Escape": "Esc"
        default: key.uppercased()
        }
    }
}
