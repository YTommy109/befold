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

    /// 翻訳が解決される環境でもキーのままの環境(SPM テストの一部)でも成り立つよう、
    /// 文言の中身ではなく「同じ置換で作った期待値」と比べる。名前が文言へ差し込まれる
    /// ことは `baseLabelTemplateTakesTheBranchName` がカタログで担保する。
    private static func expectedBaseLabel(_ name: String) -> String {
        String(format: String(localized: "toolbar.mode.diff.base", bundle: .l10n), name)
    }

    @Test("基準ラベルの文言はブランチ名の差し込み位置を持つ")
    func baseLabelTemplateTakesTheBranchName() throws {
        let catalog = try LocalizableCatalog.load(bundle: .l10n)
        for language in ["ja", "en"] {
            #expect(catalog["toolbar.mode.diff.base"]?[language]?.contains("%@") == true, "\(language) に %@ がありません")
        }
    }

    @Test("ラベルは解決された基準ブランチ名を出す")
    func labelShowsResolvedBaseBranch() {
        let label = ComparisonTargetPresentation.label(
            target: .parentBranch, resolution: resolution(branch: "feature-a"), isUnchanged: false
        )
        #expect(label == Self.expectedBaseLabel("feature-a"))

        let head = ComparisonTargetPresentation.label(
            target: .head,
            resolution: resolution(branch: nil),
            isUnchanged: false
        )
        #expect(head == Self.expectedBaseLabel("HEAD"))

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

    /// 差分モードへ入った直後(取得の飛行中)に、基準ラベルへ「(変更なし)」を付けない(TASK-676)。
    /// 確定した空差分でだけ付く。いずれも、`diffContent` が変わった時点でツールバーを
    /// 再同期する経路(`ViewerDiffPresenter` の `diffContentDidChange`)に依る。
    @Test("差分モードへ入った直後は「(変更なし)」を付けず、空と確定したときだけ付く", arguments: [true, false])
    func unchangedLabelOnlyAfterEmptyDiffSettles(hasDiff: Bool) async throws {
        let gate = BlockingGate()
        defer { gate.open() }
        let reader: any GitDiffReading = hasDiff
            ? TargetEchoDiffReader(held: .parentBranch, gate: gate) : HeldNoChangesReader(gate: gate)
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "ComparisonTargetTests.entry.\(hasDiff)"),
            diffDisplayPreference: DiffDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "ComparisonTargetTests.entry.pref.\(hasDiff)")
            ),
            diffLoader: GitDiffLoader(reader: reader),
            gitFileIndex: ImmediateRootGitFileIndex()
        ).controller
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        let item = try #require(controller.window?.toolbar?.items
            .first { $0.itemIdentifier == .init("diffComparison") })
        let popUp = try #require(item.view as? NSPopUpButton)
        let plain = ComparisonTargetPresentation.label(target: .parentBranch, resolution: nil, isUnchanged: false)
        let unchanged = ComparisonTargetPresentation.label(target: .parentBranch, resolution: nil, isUnchanged: true)

        controller.setDisplayMode(.diff)
        #expect(controller.store.diffContent == .pending)
        #expect(popUp.itemTitles.first == plain, "取得の飛行中は「(変更なし)」を付けない")

        gate.open()
        await controller.diffRefreshTask?.value
        #expect(popUp.itemTitles.first == (hasDiff ? plain : unchanged))
    }
}

/// 差分が空(`.noChanges`)の結果を、ゲートが開くまで止めて返す取得器。
private struct HeldNoChangesReader: GitDiffReading {
    let gate: BlockingGate

    func diff(forFileAt _: URL, in _: URL, target _: GitComparisonTarget) -> GitFileDiff? {
        gate.waitUntilOpen()
        return .noChanges
    }
}
