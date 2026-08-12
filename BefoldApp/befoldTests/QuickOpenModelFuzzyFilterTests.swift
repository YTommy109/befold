@testable import befold
import BefoldKit
import Foundation
import Testing

/// 索引ベースの候補一覧(空入力の既定表示と fuzzy 絞り込み)を検証する。
/// 一致ゼロ・打ち切りといった、候補そのものではなく**表示の状態**も含む。
@Suite
@MainActor
struct QuickOpenModelFuzzyFilterTests: QuickOpenModelTestCase {
    @Test("空入力では索引に載っている履歴のみを出す")
    func emptyQueryShowsRecentsOnly() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [
            candidate("/repo/r.md", "r.md", .recent),
            candidate("/repo/m.md", "m.md", .bookmark),
            candidate("/repo/i.md", "i.md", .indexed),
        ]
        let model = await makeModel(environment)

        // 空入力では recent(時計)のみ。bookmark・indexed は羅列しない。
        #expect(model.candidates.map(\.displayPath) == ["r.md"])
    }

    @Test("fuzzy 入力では候補を絞り込む")
    func fuzzyQueryFilters() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [
            candidate("/repo/alpha.md", "alpha.md"),
            candidate("/repo/zzz.md", "zzz.md"),
        ]
        let model = await makeModel(environment)

        model.queryText = "alp"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.displayPath) == ["alpha.md"])
    }

    @Test("候補ゼロは一致なしとして扱いエラーにしない")
    func noMatchesIsNotAnError() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md")]
        let model = await makeModel(environment)

        model.queryText = "qqq"
        await model.waitForPendingWork()

        #expect(model.candidates.isEmpty)
        #expect(model.showsNoMatches)
    }

    @Test("候補の打ち切りは表示に伝わる")
    func truncationIsSurfaced() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [candidate("/repo/a.md", "a.md")]
        environment.isTruncated = true
        let model = await makeModel(environment)

        model.queryText = "a"
        await model.waitForPendingWork()

        #expect(model.showsTruncationNotice)
    }
}
