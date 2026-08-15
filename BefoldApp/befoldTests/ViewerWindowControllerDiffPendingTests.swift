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
    private func preparePresentedMarkdown(_ controller: ViewerWindowController) async {
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controller.store.contentState.fileType == .markdown
        }
    }
}
