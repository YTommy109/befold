@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ルート解決を即座に成功させる索引。既定のフィクスチャ索引は /mock 配下で
/// リポジトリルートを返さず、取得へ到達しない。
private final class ImmediateRootGitFileIndex: GitFileIndexing, @unchecked Sendable {
    func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
        nil
    }

    func repositoryRoot(forFileAt url: URL) -> URL? {
        url.deletingLastPathComponent()
    }
}

/// ルート解決を遅らせる索引。コントローラ構築時に飛ぶ基準ディレクトリ解決が
/// 「準備を終えてもまだ着地していない」状況を決定的に作るために使う(TASK-512)。
/// `repositoryRoot(forDirectoryAt:)` はプロトコル拡張だけの実装(静的ディスパッチ)なので、
/// プロトコル要件であるこちらを遅くする。
private final class SlowRootGitFileIndex: GitFileIndexing, @unchecked Sendable {
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
        nil
    }

    func repositoryRoot(forFileAt url: URL) -> URL? {
        Thread.sleep(forTimeInterval: delay)
        return url.deletingLastPathComponent()
    }
}

/// 差分取得の未確定(.pending)まわりの store 遷移(TASK-407)。
/// 取得経路そのものの回帰は ViewerWindowControllerDiffTests が受け持つ
/// (file_length / type_body_length の上限に達したため suite を分けている)。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowControllerDiffPendingTests {
    private let file = URL(fileURLWithPath: "/mock/note.md")

    /// 差分表示へ切り替えた契機で取得を登録したら、着地まで store は「未確定」を保持する
    /// (未確定の間、レンダラはモード切替だけの再描画を見送って前の表示を残す = TASK-407)。
    @Test("差分表示への切替は着地まで未確定として扱う")
    func marksDiffPendingUntilFetchLands() async {
        let controller = makeDiffModeController(
            prefix: "DiffPendingTests.lands", result: .diff("DIFF")
        )
        defer { controller.close() }
        await preparePresentedMarkdown(controller)

        controller.setDisplayMode(.diff)

        #expect(controller.store.diffContent == .pending)
        await controller.diffRefreshTask?.value
        #expect(controller.store.diffContent == .diff("DIFF"))
    }

    /// AC#3: 差分として描けない結果(変更なし・取得失敗)が着地したら「未確定」は
    /// 「差分なし」へ確定し、表示は通常のソース表示へ進める(未確定のまま固まらない)。
    @Test("差分なしの確定で未確定が解消される")
    func resolvesPendingToUnavailableWhenNoChanges() async {
        let controller = makeDiffModeController(
            prefix: "DiffPendingTests.noChanges", result: .noChanges
        )
        defer { controller.close() }
        await preparePresentedMarkdown(controller)

        controller.setDisplayMode(.diff)

        #expect(controller.store.diffContent == .pending)
        await controller.diffRefreshTask?.value
        #expect(controller.store.diffContent == .unavailable)
    }

    /// 確定差分を表示中の取り直し(保存などによる再取得)では未確定へ降格しない。
    /// 降格すると、着地までの間だけ差分ハイライトが消える中間状態が新たに生まれる。
    @Test("表示中の差分は取り直しで未確定に降格しない")
    func keepsDisplayedDiffDuringRefetch() async {
        let controller = makeDiffModeController(
            prefix: "DiffPendingTests.noDowngrade", result: .diff("DIFF")
        )
        defer { controller.close() }
        await preparePresentedMarkdown(controller)
        controller.setDisplayMode(.diff)
        await controller.diffRefreshTask?.value
        #expect(controller.store.diffContent == .diff("DIFF"))

        controller.refreshDiff()

        #expect(controller.store.diffContent == .diff("DIFF"))
        await controller.diffRefreshTask?.value
        #expect(controller.store.diffContent == .diff("DIFF"))
    }

    /// 取得飛行中(.pending)に差分表示を離れたら未確定が解消される。この経路の書き手は
    /// ViewerDocumentPresenter.applyDisplayMode と refresh() の guard の 2 つで二重に
    /// 被覆されている(片方を外しただけでは通る。両方外すと落ちることを実測済み)。
    /// pending が残留するとレンダラがモード切替を見送り続け、前の表示が固まったままになる。
    @Test("取得飛行中に差分表示を離れると未確定が解消される")
    func leavingDiffModeResolvesPending() async {
        let controller = makeDiffModeController(
            prefix: "DiffPendingTests.leave", result: .diff("DIFF")
        )
        defer { controller.close() }
        await preparePresentedMarkdown(controller)
        controller.setDisplayMode(.diff)
        #expect(controller.store.diffContent == .pending)

        controller.setDisplayMode(.source)

        #expect(controller.store.diffContent == .unavailable)
        // 離脱前に飛ばした取得が遅れて着地しても書き戻されない(着地時の一致確認)。
        await controller.diffRefreshTask?.value
        #expect(controller.store.diffContent == .unavailable)
    }

    /// TASK-512: サイドバーの基準ディレクトリ解決が遅れて着地しても、確定済みの
    /// 差分状態が未確定へ戻らない。準備ヘルパーが解決を待ち切っていないと、着地時の
    /// `gitContextDidChange()` → `refreshDiff()` が `.unavailable` を `.pending` へ
    /// 戻し、CI(負荷の高いマシン)でだけ落ちる。
    /// 修正(preparePresentedDocument の awaitSettled)を戻すと、最後の期待が
    /// `.pending` で落ちることを実測で確認している。
    @Test("サイドバーの基準ディレクトリ解決が遅れて着地しても確定状態が壊れない")
    func keepsResolvedDiffWhenBaseDirectoryResolutionLandsLate() async {
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# note",
            defaults: makeIsolatedDefaults(prefix: "DiffPendingTests.lateResolve"),
            diffDisplayPreference: DiffDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "DiffPendingTests.lateResolve.pref")
            ),
            diffLoader: GitDiffLoader(reader: StubDiffReader(result: .noChanges)),
            gitFileIndex: SlowRootGitFileIndex(delay: 0.5)
        ).controller
        defer { controller.close() }
        await preparePresentedMarkdown(controller)

        // 準備を抜けた時点で解決は着地済み。ここが nil なら解決はまだ飛行中で、
        // 後から着地した `gitContextDidChange()` が確定済みの状態を `.pending` へ戻す
        // (CI で落ちた形そのもの)。共有ヘルパーの awaitSettled を外すとここで落ちる。
        #expect(controller.fileListModel.baseDirectory != nil)

        controller.setDisplayMode(.diff)
        await controller.diffRefreshTask?.value
        #expect(controller.store.diffContent == .unavailable)

        // 解決が残っていればここで着地する。待ち切れていれば即座に戻り、状態は動かない。
        await controller.sidebar.awaitSettled()

        #expect(controller.store.diffContent == .unavailable)
    }

    /// 取得へ到達できる差分表示用のコントローラ。
    private func makeDiffModeController(prefix: String, result: GitFileDiff) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, contents: "# note",
            defaults: makeIsolatedDefaults(prefix: prefix),
            diffDisplayPreference: DiffDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "\(prefix).pref")
            ),
            diffLoader: GitDiffLoader(reader: StubDiffReader(result: result)),
            gitFileIndex: ImmediateRootGitFileIndex()
        ).controller
    }

    /// レンダリング表示のまま提示状態を作る(presentDocument は差分表示にしてしまう)。
    /// 待ち合わせは差分系で共有する preparePresentedDocument が行う(TASK-512)。
    private func preparePresentedMarkdown(_ controller: ViewerWindowController) async {
        await preparePresentedDocument(in: controller, file: file)
        #expect(controller.store.contentState.fileType == .markdown)
    }
}
