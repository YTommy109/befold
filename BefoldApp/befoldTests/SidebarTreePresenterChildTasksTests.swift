@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// `SidebarTreePresenter.childTasks` の待ち合わせは有効な取得だけを待ち(TASK-644)、
/// 無効化済みの取得は着地で自分を片付ける(TASK-652)。
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

    /// 予約した組み直しを、返したゲートが開くまで走らせない。着地(予約)と予約の実行は
    /// どちらもメインアクターの別ジョブで、間にテストが入れる保証は無い(TASK-661)。
    private func holdScheduledRebuild(_ presenter: SidebarTreePresenter) -> AsyncGate {
        let hold = AsyncGate()
        presenter.scheduledRebuildHold = { await hold.wait() }
        return hold
    }

    @Test("組み直しの予約中に畳むと、同期の組み直しが予約を捨て、組み直しは 1 回で済む")
    func collapseDropsScheduledRebuild() async throws {
        let presenter = makePresenter()
        let hold = holdScheduledRebuild(presenter)
        defer { hold.open() }
        let key = base.appendingPathComponent("a").normalizedPathKey
        expand(presenter, "a")
        // 予約は止めてあるので、立てば立ったまま残る。
        for _ in 0 ..< 10000 where !presenter.hasPendingRebuild {
            await Task.yield()
        }
        try #require(presenter.hasPendingRebuild)

        presenter.collapseFolder(key)

        // 畳みが同期で組み直した。予約が残っていれば、同じ材料でもう 1 回組む。
        #expect(!presenter.hasPendingRebuild)
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
        let hold = holdScheduledRebuild(presenter)
        try #require(presenter.expandedKeys == [base.appendingPathComponent("a").normalizedPathKey])
        gate.open()
        // 予約は止めてあるので、立てば立ったまま残る。
        for _ in 0 ..< 10000 where !presenter.hasPendingRebuild {
            await Task.yield()
        }
        try #require(presenter.hasPendingRebuild)

        presenter.invalidateExpansion()

        #expect(!presenter.hasPendingRebuild)
        // 予約が残っていれば、下の awaitSettled がそれを待って走らせ、展開を開き直す。
        hold.open()
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
        // 捨てた取得は awaitSettled の待ち対象に無い。返った後、組み直しが予約されるなら
        // 観測できるまで譲る。
        for _ in 0 ..< 10000 where returned.get() == 0 || !presenter.hasPendingRebuild {
            await Task.yield()
        }
        try #require(returned.get() == 1)
        // 無効化の経路は `childTasks` を触らないので、残っていれば着地で片付けたはず。
        for _ in 0 ..< 10000 where presenter.retainedChildTaskCount > 0 {
            await Task.yield()
        }
        #expect(presenter.retainedChildTaskCount == 0)

        #expect(!presenter.hasPendingRebuild)
        await presenter.awaitSettled()
        #expect(issued.get() == 1)
        #expect(presenter.expandedKeys.isEmpty)
    }
}
