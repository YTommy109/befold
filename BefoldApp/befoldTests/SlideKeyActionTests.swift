import AppKit
@testable import befold
import Testing

/// スライド窓のキー割り当て(TASK-593.3)。
///
/// GUI 層は自動テスト対象外なので、「修飾キー付きは素通しされる」「検索欄に入力中は
/// 素通しされる」を測れるのはこの純粋関数のテストだけになる。
struct SlideKeyActionTests {
    private func action(
        _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = [], editing: Bool = false
    ) -> SlideKeyAction {
        SlideKeyAction.action(keyCode: keyCode, modifiers: modifiers, isEditingText: editing)
    }

    @Test("Space と ↓ が次のファイル")
    func spaceAndDownGoNext() {
        #expect(action(SlideKeyAction.KeyCode.space) == .next)
        #expect(action(SlideKeyAction.KeyCode.downArrow) == .next)
    }

    @Test("Shift+Space と Backspace と ↑ が前のファイル")
    func shiftSpaceBackspaceAndUpGoPrevious() {
        #expect(action(SlideKeyAction.KeyCode.space, .shift) == .previous)
        #expect(action(SlideKeyAction.KeyCode.delete) == .previous)
        #expect(action(SlideKeyAction.KeyCode.upArrow) == .previous)
    }

    /// shift だけは Shift+Space に使うので通す。↓ / ↑ / Backspace に shift が付いた場合も
    /// 素通しにはしない（誤爆より、押した方向へ動くほうが説明できる）。
    @Test("Shift は素通しの対象にしない")
    func shiftDoesNotSuppress() {
        #expect(action(SlideKeyAction.KeyCode.downArrow, .shift) == .next)
        #expect(action(SlideKeyAction.KeyCode.upArrow, .shift) == .previous)
    }

    @Test("⌘ / ⌥ / ⌃ 付きはすべて素通しする", arguments: [
        NSEvent.ModifierFlags.command, .option, .control,
    ])
    func commandOptionControlPassThrough(modifier: NSEvent.ModifierFlags) {
        for keyCode in [
            SlideKeyAction.KeyCode.space, SlideKeyAction.KeyCode.delete,
            SlideKeyAction.KeyCode.upArrow, SlideKeyAction.KeyCode.downArrow,
        ] {
            #expect(action(keyCode, modifier) == .ignored, "keyCode \(keyCode) が消費された")
        }
    }

    @Test("テキスト入力中はすべて素通しする")
    func editingTextPassesEverythingThrough() {
        for keyCode in [
            SlideKeyAction.KeyCode.space, SlideKeyAction.KeyCode.delete,
            SlideKeyAction.KeyCode.upArrow, SlideKeyAction.KeyCode.downArrow,
        ] {
            #expect(action(keyCode, editing: true) == .ignored, "keyCode \(keyCode) が消費された")
        }
    }

    @Test("担当外のキーは素通しする")
    func otherKeysPassThrough() {
        // ← (123) / → (124) / return (36)。スライド窓はこれらに割り当てを持たない。
        for keyCode in [UInt16(123), 124, 36] {
            #expect(action(keyCode) == .ignored)
        }
    }
}
