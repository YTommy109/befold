@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// 見出しジャンプのレベル設定が「次に開く窓の出発点」として保存・復元されることを検証する。
///
/// 要点は **未設定と「3 つとも OFF」の区別**。Bool 3 本で保存すると
/// `UserDefaults.bool(forKey:)` が未設定時 false を返すため両者が同じになり、
/// ユーザーが 3 つとも OFF にした状態が次の窓で既定へ戻る。
@Suite
@MainActor
struct HeadingJumpLevelDefaultsTests {
    @Test("保存値が無ければ h1 / h2 / h3 すべてが目印になる")
    func defaultsToAllLevelsWhenUnset() {
        let defaults = makeIsolatedDefaults(prefix: "HeadingJumpLevelDefaultsTests.unset")

        let store = HeadingJumpLevelDefaults(defaults: defaults)

        #expect(store.levels == .default)
        #expect(store.levels.levels == [1, 2, 3])
    }

    @Test("3 つとも OFF にした状態は、次に読み直しても既定へ戻らない")
    func keepsEmptySelectionAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "HeadingJumpLevelDefaultsTests.empty")
        HeadingJumpLevelDefaults(defaults: defaults).record(HeadingJumpLevels(levels: []))

        let reopened = HeadingJumpLevelDefaults(defaults: defaults)

        #expect(reopened.levels == HeadingJumpLevels(levels: []))
        #expect(reopened.levels.levels.isEmpty)
    }

    @Test("一部だけ ON にした状態がそのまま復元される")
    func restoresPartialSelection() {
        let defaults = makeIsolatedDefaults(prefix: "HeadingJumpLevelDefaultsTests.partial")
        HeadingJumpLevelDefaults(defaults: defaults).record(HeadingJumpLevels(levels: [2]))

        let reopened = HeadingJumpLevelDefaults(defaults: defaults)

        #expect(reopened.levels.levels == [2])
        #expect(reopened.levels.levels.contains(2))
        #expect(!reopened.levels.levels.contains(1))
    }

    @Test("記録は後勝ちで、最後に操作した状態が残る")
    func recordsLastWriteWins() {
        let defaults = makeIsolatedDefaults(prefix: "HeadingJumpLevelDefaultsTests.lastWrite")
        let store = HeadingJumpLevelDefaults(defaults: defaults)

        store.record(HeadingJumpLevels(levels: [1]))
        store.record(HeadingJumpLevels(levels: [1, 3]))

        #expect(HeadingJumpLevelDefaults(defaults: defaults).levels.levels == [1, 3])
    }
}

/// 値型そのものの規則（正規化と保存表現の往復）。
@Suite
struct HeadingJumpLevelsTests {
    @Test("レベルは昇順・重複なしに正規化され、範囲外は落ちる")
    func normalizesLevels() {
        #expect(HeadingJumpLevels(levels: [3, 1, 2, 1]).levels == [1, 2, 3])
        #expect(HeadingJumpLevels(levels: [0, 4, 6]).levels.isEmpty)
    }

    @Test("保存表現は h1 / h2 / h3 の形")
    func storedValueUsesHeadingTokens() {
        #expect(HeadingJumpLevels(levels: [1, 3]).storedValue == ["h1", "h3"])
        #expect(HeadingJumpLevels(levels: []).storedValue.isEmpty)
    }

    @Test("未設定(nil)は既定へ倒れ、空配列は 3 つとも OFF として尊重される")
    func distinguishesUnsetFromEmpty() {
        #expect(HeadingJumpLevels.stored(nil) == .default)
        #expect(HeadingJumpLevels.stored([]) == HeadingJumpLevels(levels: []))
    }

    @Test("壊れた保存値は落として読む")
    func ignoresBrokenTokens() {
        #expect(HeadingJumpLevels.stored(["h2", "x", "h9", ""]).levels == [2])
    }
}
