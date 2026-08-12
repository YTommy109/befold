@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 候補集合の**非同期到着**と入力の競合を検証する。init が候補集合を待たずに返ること、
/// 到着より後の入力が古い世代の結果で上書きされないこと、列挙がキーストロークの
/// 延長で走らないことを固定する。
@Suite
@MainActor
struct QuickOpenModelCandidateSetArrivalTests: QuickOpenModelTestCase {
    @Test("候補集合の到着前でも init は返り、入力を受け付ける")
    func modelIsUsableBeforeCandidateSetArrives() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md", .recent)]
        let released = AsyncGate()
        environment.candidateSetGate = { await released.wait() }

        // 候補集合を止めたまま init する。ここで返ってくること自体が「パネル即時表示」の根拠。
        let model = QuickOpenModel(environment: environment, onOpen: { _ in })
        #expect(model.candidates.isEmpty)

        // 到着前でも入力は受け付ける(空集合に対する絞り込みが走るだけ)。
        model.queryText = "alp"
        #expect(model.candidates.isEmpty)

        released.open()
        await model.waitForPendingWork()

        // 到着後、その時点の入力に対する絞り込み結果へ差し替わる。
        #expect(model.candidates.map(\.displayPath) == ["alpha.md"])
    }

    @Test("候補集合の到着より後の入力が優先される(古い世代の結果で上書きしない)")
    func laterQueryWinsOverArrivingCandidateSet() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [
            candidate("/repo/alpha.md", "alpha.md", .recent),
            candidate("/repo/zulu.md", "zulu.md", .recent),
        ]
        let released = AsyncGate()
        environment.candidateSetGate = { await released.wait() }

        let model = QuickOpenModel(environment: environment, onOpen: { _ in })
        model.queryText = "zul"
        released.open()
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.displayPath) == ["zulu.md"])
    }

    @Test("パスモードの列挙はキーストロークの延長では走らない")
    func pathModeEnumerationDoesNotRunInline() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold")]
        let model = await makeModel(environment)

        model.queryText = "/dev/be"

        // setter から戻った時点ではまだ列挙結果が入っていない = 呼び出し元を待たせていない。
        #expect(model.candidates.isEmpty)

        await model.waitForPendingWork()
        #expect(model.candidates.map(\.url) == [url("/dev/befold")])
    }
}
