import BefoldKit
import Testing

/// 検索の件数表示の書式（TASK-570）。
///
/// **web 面（`viewer-src/navigation.ts` の `formatNavigationCount`）と同じ書式**で
/// なければならない。共有できない実装なので、ここで書式そのものを固定する。
/// このテストが落ちたら、直す前に `navigation.ts` 側と食い違っていないかを見ること。
@Suite
struct FindMatchCounterTests {
    @Test("ヒットがあれば 1 始まりの現在位置と総数を n/N で表す")
    func showsOneBasedPositionOverTotal() {
        #expect(FindMatchCounter.text(currentIndex: 0, count: 12) == "1/12")
        #expect(FindMatchCounter.text(currentIndex: 2, count: 12) == "3/12")
        #expect(FindMatchCounter.text(currentIndex: 11, count: 12) == "12/12")
    }

    /// 0 件でも専用の文言は出さない。バー幅が伸縮しないよう件数表示のまま固定する
    /// （web 面と同じ判断）。
    @Test("ヒット 0 件は 0/0")
    func showsZeroOverZeroWithoutMatches() {
        #expect(FindMatchCounter.text(currentIndex: -1, count: 0) == "0/0")
        #expect(FindMatchCounter.text(currentIndex: 0, count: 0) == "0/0")
    }

    /// 検索は始まったがまだ 1 件目を選んでいない状態。1 件目を指したことにしない。
    @Test("未選択のあいだは現在位置を 0 として表す")
    func showsZeroPositionWhileNothingSelected() {
        #expect(FindMatchCounter.text(currentIndex: -1, count: 5) == "0/5")
    }
}
