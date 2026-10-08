import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 差分の比較基準(TASK-353.2)のうち、窓をまたがない単体の保証。
/// 窓ごとの独立は `ViewerWindowManagerDiffTests`、取得の合流・キャッシュは
/// `GitDiffLoaderTests` / `GitStatusStoreTests` が持つ。
@MainActor
struct ComparisonTargetTests {
    private let file = URL(fileURLWithPath: "/mock/note.swift")

    private func resolution(
        branch: String? = "main", differs: Bool = false
    ) -> GitComparisonResolution {
        GitComparisonResolution(baseID: "abc", baseBranch: branch, parentDiffersFromDefault: differs, degraded: false)
    }

    /// 基準を変えた瞬間に旧基準の取得が着地しても、その本文は書き戻されない。
    /// 着地時の照合(`store.comparisonTarget == 取得時の target`)を外すと、URL もモードも
    /// 一致したまま旧基準の差分が新しいラベルの下に出る。
    @Test("基準を変えた後に旧基準の差分が着地しても書き戻さない", testTimeLimit())
    func oldTargetDiffDoesNotLand() async {
        let gate = BlockingGate()
        defer { gate.open() }
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "ComparisonTargetTests.landing"),
            diffDisplayPreference: DiffDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "ComparisonTargetTests.landing.pref")
            ),
            diffLoader: GitDiffLoader(reader: TargetEchoDiffReader(held: .parentBranch, gate: gate)),
            gitFileIndex: ImmediateRootGitFileIndex()
        ).controller
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        controller.store.displayMode = .diff
        controller.refreshDiff()
        let oldFetch = controller.diffRefreshTask
        #expect(controller.store.diffContent == .pending)

        controller.setComparisonTarget(.head)
        // 基準を変えた時点で、旧基準の差分(確定済みでも)は未確定へ落ちる。
        #expect(controller.store.diffContent == .pending)
        gate.open()
        await oldFetch?.value

        #expect(controller.store.diffContent != .diff("DIFF-parentBranch"))
    }

    @Test("新しい窓の基準は常に「このブランチの変更」")
    func newWindowStartsFromParentBranch() {
        #expect(ViewerStore().comparisonTarget == .parentBranch)
    }

    @Test("スタック全体の変更は親ブランチがデフォルトと異なるときだけ選べる")
    func stackTargetAppearsOnlyWhenParentDiffers() {
        let same = ComparisonTargetPresentation.selectableTargets(resolution: resolution(differs: false))
        let stacked = ComparisonTargetPresentation.selectableTargets(resolution: resolution(differs: true))

        #expect(same == [.parentBranch, .head])
        #expect(stacked == [.parentBranch, .defaultBranch, .head])
        #expect(ComparisonTargetPresentation.selectableTargets(resolution: nil) == [.parentBranch, .head])
    }

    @Test("ラベルは解決された基準ブランチ名を出す")
    func labelShowsResolvedBaseBranch() {
        let label = ComparisonTargetPresentation.label(
            target: .parentBranch, resolution: resolution(branch: "feature-a"), isUnchanged: false
        )
        #expect(label.contains("feature-a"))

        let head = ComparisonTargetPresentation.label(
            target: .head,
            resolution: resolution(branch: nil),
            isUnchanged: false
        )
        #expect(head.contains("HEAD"))

        let unchanged = ComparisonTargetPresentation.label(
            target: .parentBranch, resolution: resolution(), isUnchanged: true
        )
        #expect(unchanged != ComparisonTargetPresentation.label(
            target: .parentBranch, resolution: resolution(), isUnchanged: false
        ))
    }

    /// 比較基準のラベル兼ポップアップは差分モードのときだけ見え、選択中の基準にチェックが付く。
    @Test("比較基準アイテムは差分モードのときだけ見える")
    func comparisonItemIsVisibleOnlyInDiffMode() throws {
        let controller = ViewerWindowControllerFixture(
            file: URL(fileURLWithPath: "/mock/a.mmd"), prefix: "ComparisonTargetTests.toolbar"
        ).controller
        defer { controller.close() }
        let items = try #require(controller.window?.toolbar?.items)
        let item = try #require(items.first { $0.itemIdentifier == .init("diffComparison") })
        let popUp = try #require(item.view as? NSPopUpButton)
        controller.store.displayMode = .source
        controller.refreshUIState()
        #expect(popUp.isHidden)

        controller.store.displayMode = .diff
        controller.refreshUIState()
        #expect(!popUp.isHidden)
        // 先頭はラベル。選択肢は既定で「このブランチ」「作業中」(スタック全体は親が分かるときだけ)。
        #expect(popUp.itemTitles.count == 3)
        #expect(popUp.menu?.items[1].state == .on)

        controller.setComparisonTarget(.head)
        controller.refreshUIState()
        #expect(popUp.menu?.items[2].state == .on)
        #expect(popUp.menu?.items[1].state == .off)
    }
}
