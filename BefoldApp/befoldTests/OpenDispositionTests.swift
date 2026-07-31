import AppKit
import BefoldKit
import Testing

@Suite
struct OpenDispositionTests {
    @Test("無修飾クリックは今のウィンドウで開く")
    func plainClickOpensInCurrentTab() {
        #expect(OpenDisposition(commandKey: false, shiftKey: false) == .currentTab)
    }

    @Test("cmd+クリックは別タブで開く")
    func commandClickOpensInNewTab() {
        #expect(OpenDisposition(commandKey: true, shiftKey: false) == .newTab)
    }

    @Test("cmd+shift+クリックは新規ウィンドウで開く")
    func commandShiftClickOpensInNewWindow() {
        #expect(OpenDisposition(commandKey: true, shiftKey: true) == .newWindow)
    }

    @Test("shift 単独は無修飾と同じ扱いにする")
    func shiftAloneFallsBackToCurrentTab() {
        #expect(OpenDisposition(commandKey: false, shiftKey: true) == .currentTab)
    }

    @Test("NSEvent.ModifierFlags からも同じ対応表で解釈する")
    func modifierFlagsUseSameTable() {
        #expect(OpenDisposition(modifiers: []) == .currentTab)
        #expect(OpenDisposition(modifiers: [.command]) == .newTab)
        #expect(OpenDisposition(modifiers: [.command, .shift]) == .newWindow)
    }

    @Test("ctrl や option は開き方に影響しない")
    func otherModifiersAreIgnored() {
        #expect(OpenDisposition(modifiers: [.control, .command]) == .newTab)
        #expect(OpenDisposition(modifiers: [.option]) == .currentTab)
    }
}
