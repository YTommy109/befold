@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// `SidebarTreePresenter.childTasks` は走行中の有効な取得だけを持つ(TASK-644)。
@Suite
@MainActor
struct SidebarTreePresenterChildTasksTests {
    private let base = URL(fileURLWithPath: "/tmp/befold-task-644")

    private func makePresenter(gate: AsyncGate? = nil) -> SidebarTreePresenter {
        SidebarTreePresenter(
            fileListModel: FileListModel(currentDirectory: base, entries: [], selection: nil),
            childrenLister: { url, _, _ in
                // `deep` の取得だけをテストが解放するまで止める。
                if url.lastPathComponent == "deep" { await gate?.wait() }
                return []
            }
        )
    }

    private func expand(_ presenter: SidebarTreePresenter, _ relative: String) {
        let url = base.appendingPathComponent(relative)
        presenter.expandFolder(url.normalizedPathKey, at: url)
    }

    @Test("配下の取得を止めたまま親を畳んでも、awaitSettled は無効化済みの取得を待たない")
    func collapsingParentDropsDescendantTasks() async throws {
        let gate = AsyncGate()
        defer { gate.open() }
        let presenter = makePresenter(gate: gate)
        expand(presenter, "a")
        expand(presenter, "a/deep")

        presenter.collapseFolder(base.appendingPathComponent("a").normalizedPathKey)

        // 残っていると、下の awaitSettled が止めたままの取得を待ってハングする。
        // ハングで固まらないよう、先に落とす(ゲート待ちはキャンセルに応じず `.timeLimit` でも
        // 打ち切れない。壁時計の期限で測る形は full suite の MainActor 直列化で遅れて不安定)。
        try #require(presenter.pendingChildKeys.isEmpty)
        await presenter.awaitSettled()
    }

    @Test("子リストが着地したキーは走行中の取得に残らない")
    func landedTaskRemovesItself() async {
        let presenter = makePresenter()
        expand(presenter, "a")
        expand(presenter, "b")
        #expect(presenter.pendingChildKeys.count == 2)

        await presenter.awaitSettled()

        #expect(presenter.pendingChildKeys.isEmpty)
    }
}
