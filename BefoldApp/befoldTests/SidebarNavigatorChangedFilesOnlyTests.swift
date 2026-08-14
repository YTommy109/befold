@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 「変更ファイルのみ表示」トグルの反映経路を検証する(TASK-291 / TASK-296 / TASK-303)。
/// SidebarNavigatorGitStatusTests から分離し、両者は RecordingWatcher を共有する。
@Suite
@MainActor
struct SidebarNavigatorChangedFilesOnlyTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// 「変更ファイルのみ表示」のトグル方向 2 種。ON へ倒すときだけ git 状態を取り直し、
    /// どちらの方向でも再列挙は走らないことを同じ計測で比べる。
    private struct ChangedFilesOnlyApply: CustomTestStringConvertible {
        let name: String
        /// 一時ディレクトリ名に使う ASCII 識別子(ケースごとに一意)。
        let key: String
        /// 初期読み込み時点の「変更ファイルのみ表示」。
        let initialState: Bool
        /// 適用後の「変更ファイルのみ表示」。
        let targetState: Bool
        let apply: @MainActor (SidebarNavigator) -> Void
        /// 適用後に増える git 取得回数。
        let expectedGitCalls: Int
        var testDescription: String {
            name
        }
    }

    private nonisolated static let changedFilesOnlyApplies: [ChangedFilesOnlyApply] = [
        // 「変更ファイルのみ表示」は手元の一覧と git 状態に対する表示述語でしかない。
        // 不可視ファイル表示と同じ再読み込みを流用すると、トグルのたびに全ウィンドウで
        // ディレクトリ全列挙と git status が走る(実測でウィンドウ 3 枚 ≒ 380ms / TASK-291)。
        // 作業ツリーの編集は `.git/index` を動かさないため index 監視では発火せず、キーウィンドウの
        // ままなら windowDidBecomeKey も再発火しない。トグル時に取り直さないと古いスナップショットの
        // まま絞り込まれる(TASK-296)。再列挙が増えないことは TASK-291 の性質の維持を意味する。
        ChangedFilesOnlyApply(
            name: "ON へのトグル適用", key: "toggle-on", initialState: false, targetState: true,
            apply: { $0.applyDisplayChange(.toggleChangedFilesOnly) }, expectedGitCalls: 1
        ),
        // OFF への切り替えは絞り込みをやめるだけで、新しい git 状態を必要としない。バッジは
        // 手元のスナップショットで足りる。方向を見ずに取り直すと、トグルのたびに開いている
        // ウィンドウ数だけ git status サブプロセスが同時に起動する(TASK-303)。
        ChangedFilesOnlyApply(
            name: "OFF へのトグル適用", key: "toggle-off", initialState: true, targetState: false,
            apply: { $0.applyDisplayChange(.toggleChangedFilesOnly) }, expectedGitCalls: 0
        ),
    ]

    @Test(
        "変更ファイルのみ表示の反映では再列挙は走らず、git 取得は経路ごとの回数だけ走る",
        arguments: changedFilesOnlyApplies
    )
    private func applyingChangedFilesOnlyPreference(_ testCase: ChangedFilesOnlyApply) async {
        let prefix = "SidebarNavigatorChangedFilesOnlyTests-\(testCase.key)"
        let base = Self.home.appendingPathComponent(prefix)
        let listings = LockedBox<Int>(0)
        let gitCalls = LockedBox<Int>(0)
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: prefix)
        )
        preference.record { $0.showChangedFilesOnly = testCase.initialState }
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            displayDefaults: preference,
            directoryLister: { _, _, _ in
                listings.update { $0 += 1 }
                return .empty
            },
            git: SidebarGitReadingStub(statuses: { _, _ in
                gitCalls.update { $0 += 1 }
                return .empty
            }),
            makeGitIndexWatcher: { url, onChange in RecordingWatcher(path: url, fire: onChange) }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.awaitSettled()
        let listingsAfterLoad = listings.get()
        let gitCallsAfterLoad = gitCalls.get()

        // トグルは窓のライブ値を反転する。既定値ストアへ書き戻されるのは結果であって入力ではない。
        testCase.apply(navigator)
        // 取得は非同期なので、発行されていれば待つと件数が増える。増えなければ発行されていない。
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.showChangedFilesOnly == testCase.targetState)
        #expect(listings.get() == listingsAfterLoad)
        #expect(gitCalls.get() == gitCallsAfterLoad + testCase.expectedGitCalls)
    }

    /// TASK-293 の不変条件そのものを検証する。絞り込み ON では、一覧と git 状態を
    /// **同じタスクで取り、同じメインアクター実行で一緒に反映する**。別タスクへ分けると
    /// 完了順が保証されず、新しい一覧だけが先に描画される間だけ絞り込みが縮退して
    /// 全件が一瞬見える。
    ///
    /// この不変条件は今まで `SidebarGitStatusCoordinator.pendingTask` の doc の散文
    /// としてだけ存在し、ON の反映を `applyWhenReady` 側へ載せ替えても何も落ちなかった
    /// (`SidebarNavigator.awaitSettled()` は両方を待つので、待ち合わせ側でも検出できない)。
    /// 載せ替えたときにここが落ちる。
    ///
    /// 反映の中身(一覧が出た時点で絞り込みが縮退していないこと)は
    /// `SidebarNavigatorListingCoherenceTests` が見るので、ここは載せる先だけを見る。
    @Test("絞り込み ON では git 状態の反映が一覧タスクに載る(単発の取得タスクは発行されない)")
    func changedFilesOnlyCouplesGitStatusIntoListingTask() async {
        let prefix = "SidebarNavigatorChangedFilesOnlyTests-coupling"
        let base = Self.home.appendingPathComponent(prefix)
        let gitCalls = LockedBox<Int>(0)
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: prefix)
        )
        preference.record { $0.showChangedFilesOnly = true }
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            displayDefaults: preference,
            directoryLister: { _, _, _ in .empty },
            git: SidebarGitReadingStub(statuses: { _, _ in
                gitCalls.update { $0 += 1 }
                return .empty
            }),
            makeGitIndexWatcher: { url, onChange in RecordingWatcher(path: url, fire: onChange) }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()

        // 一覧タスクは発行され、単発の git 取得タスクは発行されていない。
        #expect(navigator.pendingListingTask != nil)
        #expect(navigator.pendingGitStatusTask == nil)

        // それでも git は取得されている(取得が一覧タスクの中で待たれている)。
        await navigator.pendingListingTask?.value
        #expect(gitCalls.get() == 1)
        #expect(navigator.pendingGitStatusTask == nil)
    }
}
