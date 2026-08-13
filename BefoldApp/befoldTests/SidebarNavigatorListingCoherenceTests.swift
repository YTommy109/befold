@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 一覧と git 状態が「一緒に」反映されることを検証する(TASK-293)。
///
/// 別々に反映すると、新しいディレクトリの一覧だけが先に届いている間だけ絞り込みが
/// 縮退し(状態が別ディレクトリのものなので絞り込まない)、全件が一瞬描画されてから
/// 絞り込まれる。縮退そのものは TASK-285 の意図した振る舞いなので、縮退を消すのではなく
/// 縮退が起きる空白期間そのものを無くす。
/// 親移動行を持たない、ファイルだけの列挙結果。directoryLister スタブの戻り値を
/// 1 行に収めるためのヘルパー(展開もソートもこのテストの関心ではない)。
private func fileListing(_ urls: URL...) -> DirectoryListing {
    DirectoryListing(rootChildren: urls.map { FileListEntry(url: $0, kind: .file) })
}

@Suite
@MainActor
struct SidebarNavigatorListingCoherenceTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    @Test("フォルダー移動では、一覧が反映された時点で git 状態も揃っている")
    func appliesListingAndGitStatusTogether() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let changed = dirB.appendingPathComponent("changed.md")
        let clean = dirB.appendingPathComponent("clean.md")
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorListingCoherenceTests")
        )
        preference.showChangedFilesOnly = true
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in
                fileListing(changed, clean)
            },
            git: SidebarGitReadingStub(statuses: { directory, _ in
                // git は列挙より遅れて返る。この間に一覧だけを反映してはならない。
                guard directory.normalizedPathKey == dirB.normalizedPathKey else { return .empty }
                for _ in 0 ..< 50 {
                    await Task.yield()
                }
                let status = GitFileStatus(indexChange: nil, worktreeChange: .modified)
                return GitStatusResult(
                    snapshot: GitStatusSnapshot(statuses: [changed.normalizedPathKey: status], indexURL: nil),
                    repositoryRoot: base
                )
            })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.navigateToFolder(dirB)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.entries.count == 2)
        #expect(SidebarEmptyContext(model: navigator.fileListModel).activeGitChangeFilter != nil)
        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"]
        )
    }

    /// 絞り込みが OFF のときは一覧を git 状態と揃える理由が無い(縮退しようがない)。
    /// それでも待つと、絞り込みを使っていない利用者までフォルダー移動のたびに
    /// git subprocess の完了を待たされる(TASK-297)。
    @Test("絞り込み OFF のフォルダー移動は git 状態の完了を待たずに一覧を反映する")
    func appliesListingWithoutWaitingForGitWhenFilterIsOff() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests-off")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let changed = dirB.appendingPathComponent("changed.md")
        let clean = dirB.appendingPathComponent("clean.md")
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorListingCoherenceTests-off")
        )
        preference.showChangedFilesOnly = false
        let gate = AsyncGate()
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in
                fileListing(changed, clean)
            },
            git: SidebarGitReadingStub(statuses: { directory, _ in
                guard directory.normalizedPathKey == dirB.normalizedPathKey else { return .empty }
                await gate.wait()
                let status = GitFileStatus(indexChange: nil, worktreeChange: .modified)
                return GitStatusResult(
                    snapshot: GitStatusSnapshot(statuses: [changed.normalizedPathKey: status], indexURL: nil),
                    repositoryRoot: base
                )
            })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.navigateToFolder(dirB)

        // git はゲートで足止めしたまま一覧の反映だけを待つ。`pendingListingTask?.value` を
        // 直接 await すると、退行で一覧が git 完了待ちに変わったとき(ゲートは後述の
        // gate.open() でしか開かない)テストごと無限に停止してしまう
        // (`Task<Void, Never>` は Failure が無く、外側のキャンセルでは中断できない)。
        // タイムアウト付きポーリングにすることで、退行時は待ちきれず確実に失敗させる。
        await waitUntilOnMainActor {
            navigator.fileListModel.entries.count == 2
        }

        // 一覧は git より先に反映される。git 状態はまだ届いていない(ゲートで足止め中)。
        #expect(navigator.fileListModel.entries.count == 2)
        #expect(navigator.fileListModel.gitStatus == nil)

        // 遅れて届いた git 状態は、そのあときちんと反映される(バッジ用)。
        gate.open()
        await navigator.pendingGitStatusTask?.value
        #expect(navigator.fileListModel.gitStatus?.files.isEmpty == false)
    }

    /// `.git/index` の更新とフォルダー移動が同時に起きる状況(TASK-294)。
    /// 移動の待ち合わせ中に単発の refreshGitStatuses が世代を進めても、一覧と対で取った
    /// git 状態は捨ててはならない。捨てると一覧だけが新しいディレクトリのものになり、
    /// 単発の取得が返るまで絞り込みの外れた全件が表示される。
    @Test("移動中に .git/index 由来の取得が割り込んでも一覧と対の git 状態を捨てない")
    func keepsPairedGitStatusWhenSingleRefreshInterleaves() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests-race")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let changed = dirB.appendingPathComponent("changed.md")
        let clean = dirB.appendingPathComponent("clean.md")
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorListingCoherenceTests-race")
        )
        preference.showChangedFilesOnly = true
        let navigator = SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in
                fileListing(changed, clean)
            },
            git: SidebarGitReadingStub(statuses: { directory, policy in
                // 割り込む単発の取得。返らないまま結果を待たせ、一覧と対の結果だけで
                // 絞り込みが成立することを見る。
                guard policy == .always else {
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                    return .empty
                }
                guard directory.normalizedPathKey == dirB.normalizedPathKey else { return .empty }
                for _ in 0 ..< 50 {
                    await Task.yield()
                }
                let status = GitFileStatus(indexChange: nil, worktreeChange: .modified)
                return GitStatusResult(
                    snapshot: GitStatusSnapshot(statuses: [changed.normalizedPathKey: status], indexURL: nil),
                    repositoryRoot: base
                )
            })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.navigateToFolder(dirB)
        let listingTask = navigator.pendingListingTask
        // 移動の待ち合わせ中に `.git/index` の発火が届く。
        navigator.refreshGitStatuses(policy: .onlyIfIndexChanged)
        await listingTask?.value

        #expect(navigator.fileListModel.entries.count == 2)
        #expect(SidebarEmptyContext(model: navigator.fileListModel).activeGitChangeFilter != nil)
        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"]
        )
    }

    /// 結合適用は「一覧と対だから捨てない」だけでよく、後から始まった取得より新しいふりを
    /// してはならない(TASK-299)。世代を強制的に進めると、待ち合わせ中に届いた新しい
    /// git 状態を古いスナップショットで上書きしてしまう。
    @Test("結合適用は、後から始まって先に届いた新しい git 状態を上書きしない")
    func doesNotOverwriteNewerGitStatusAppliedWhileCoupledFetchIsPending() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests-stale")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let navigator = Self.makeRaceNavigator(
            base: base, dirB: dirB, prefix: "SidebarNavigatorListingCoherenceTests-stale",
            slowPolicy: .always
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.navigateToFolder(dirB)
        let listingTask = navigator.pendingListingTask
        // 移動の待ち合わせ中に外部で git 状態が変わり、`.git/index` 監視が新しい状態を先に適用する。
        navigator.refreshGitStatuses(policy: .onlyIfIndexChanged)
        await navigator.pendingGitStatusTask?.value
        await listingTask?.value

        #expect(navigator.fileListModel.entries.count == 2)
        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["clean.md"]
        )
    }

    /// 逆順(単発が後着)でも、後から始まった取得の結果は破棄してはならない(TASK-299)。
    @Test("結合適用のあとに着地した、より新しい git 状態が破棄されない")
    func appliesNewerGitStatusArrivingAfterCoupledApply() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorListingCoherenceTests-late")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let navigator = Self.makeRaceNavigator(
            base: base, dirB: dirB, prefix: "SidebarNavigatorListingCoherenceTests-late",
            slowPolicy: .onlyIfIndexChanged
        )
        let host = SidebarNavigatorStubHost(currentFileURL: base.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.navigateToFolder(dirB)
        let listingTask = navigator.pendingListingTask
        navigator.refreshGitStatuses(policy: .onlyIfIndexChanged)
        let singleTask = navigator.pendingGitStatusTask
        await listingTask?.value
        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"]
        )

        await singleTask?.value
        // より新しい状態(clean.md のみ変更)が反映される。changed.md が残るのは絞り込みの
        // 取りこぼしではなく、移動時に先頭行として開いた文書だから(TASK-286 / TASK-310)。
        // 開いている文書を git 絞り込みで黙って消さないのは意図した振る舞い。
        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent)
                == ["changed.md", "clean.md"]
        )
    }

    /// 結合取得(`.always`)と単発取得(`.onlyIfIndexChanged`)が別の結論を返し、
    /// どちらが遅れて返るかだけを変えられるナビゲータを作る。
    /// 結合は changed.md のみ変更、単発(= より新しい外部の変更)は clean.md のみ変更を返す。
    private static func makeRaceNavigator(
        base: URL, dirB: URL, prefix: String, slowPolicy: GitStatusRefreshPolicy
    ) -> SidebarNavigator {
        let changed = dirB.appendingPathComponent("changed.md")
        let clean = dirB.appendingPathComponent("clean.md")
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: prefix)
        )
        preference.showChangedFilesOnly = true
        return SidebarNavigator(
            currentDirectory: base,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in
                fileListing(changed, clean)
            },
            git: SidebarGitReadingStub(statuses: { directory, policy in
                if policy == slowPolicy {
                    for _ in 0 ..< 50 {
                        await Task.yield()
                    }
                }
                guard directory.normalizedPathKey == dirB.normalizedPathKey else { return .empty }
                let modified = GitFileStatus(indexChange: nil, worktreeChange: .modified)
                let target = policy == .always ? changed : clean
                return GitStatusResult(
                    snapshot: GitStatusSnapshot(statuses: [target.normalizedPathKey: modified], indexURL: nil),
                    repositoryRoot: base
                )
            })
        )
    }
}
