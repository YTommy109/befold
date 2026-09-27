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

    /// レビュー表示(ツリー × 変更のみ)で `a` の変更を持つ presenter。`a` の子リスト取得は
    /// `gate` が開くまで止まる。`issued` は取得の発行回数、`returned` は返った回数。
    private func makeReviewPresenter(
        gate: AsyncGate, issued: LockedBox<Int>, returned: LockedBox<Int>
    ) -> SidebarTreePresenter {
        let model = FileListModel(currentDirectory: base, entries: [], selection: nil)
        let presenter = SidebarTreePresenter(fileListModel: model, childrenLister: { _, _, _ in
            issued.update { $0 += 1 }
            await gate.wait()
            returned.update { $0 += 1 }
            return []
        })
        if model.display.layoutMode != .tree { model.display.apply(.toggleLayoutMode) }
        model.display.apply(.toggleChangedFilesOnly)
        let folder = base.appendingPathComponent("a")
        let changed = folder.appendingPathComponent("x.md").normalizedPathKey
        model.applyGitStatus(
            SidebarGitStatus(
                repositoryRootKey: base.normalizedPathKey,
                statuses: [changed: GitFileStatus(indexChange: nil, worktreeChange: .modified)]
            ),
            for: base, sequence: 1
        )
        presenter.applyRows(DirectoryListing(rootChildren: [FileListEntry(url: folder, kind: .folder)]), for: base)
        return presenter
    }

    @Test("子リストの着地で予約された組み直しは、展開を捨てると走らず、捨てた展開を開き直さない")
    func invalidateDropsScheduledRebuild() async throws {
        let gate = AsyncGate()
        let issued = LockedBox(0)
        let presenter = makeReviewPresenter(gate: gate, issued: issued, returned: LockedBox(0))
        try #require(presenter.expandedKeys == [base.appendingPathComponent("a").normalizedPathKey])
        gate.open()
        // 予約を観測できた時点では、まだ走っていない(走り始めに nil へ戻す)。
        for _ in 0 ..< 10000 where !presenter.hasPendingRebuild {
            await Task.yield()
        }
        try #require(presenter.hasPendingRebuild)

        presenter.invalidateExpansion()

        #expect(!presenter.hasPendingRebuild)
        await presenter.awaitSettled()
        #expect(issued.get() == 1)
        #expect(presenter.expandedKeys.isEmpty)
    }

    @Test("展開を捨てた後に古い子リストが着地しても、組み直しを予約せず開き直さない")
    func staleLandingAfterInvalidateSchedulesNothing() async throws {
        let gate = AsyncGate()
        let issued = LockedBox(0)
        let returned = LockedBox(0)
        let presenter = makeReviewPresenter(gate: gate, issued: issued, returned: returned)
        // 取得が走り出してから捨てる。
        for _ in 0 ..< 10000 where issued.get() == 0 {
            await Task.yield()
        }
        try #require(issued.get() == 1)

        presenter.invalidateExpansion()
        gate.open()
        // 捨てた取得は `childTasks` に無いので awaitSettled では待てない。返った後、
        // 組み直しが予約されるなら観測できるまで譲る。
        for _ in 0 ..< 10000 where returned.get() == 0 || !presenter.hasPendingRebuild {
            await Task.yield()
        }
        try #require(returned.get() == 1)

        #expect(!presenter.hasPendingRebuild)
        await presenter.awaitSettled()
        #expect(issued.get() == 1)
        #expect(presenter.expandedKeys.isEmpty)
    }
}
