@testable import befold
import BefoldKit
import Foundation
import Testing

/// 差分表示モードの選択可否を決める git 側の事実の導出（TASK-438.2）。
///
/// 要点は「確定した否定の事実でだけ落とす」こと。未解決・範囲外を不可へ倒すと、
/// 初期表示で無効→有効の入れ替わりが起きる。
@Suite
struct GitDiffAvailabilityTests {
    private let file = URL(fileURLWithPath: "/repo/docs/a.md")
    private let workspaceRoot = URL(fileURLWithPath: "/repo/docs")

    private func base(_ lookup: GitRootLookup) -> BaseDirectoryDescriptor {
        BaseDirectoryDescriptor(rootLookup: lookup, workspaceRoot: workspaceRoot)
    }

    private func status(_ statuses: [String: GitFileStatus], root: String = "/repo") -> SidebarGitStatus {
        SidebarGitStatus(repositoryRootKey: root, statuses: statuses)
    }

    @Test("基準ディレクトリが未解決の間は選べるまま")
    func undeterminedWhileBaseDirectoryUnresolved() {
        let availability = GitDiffAvailability.make(baseDirectory: nil, gitStatus: nil, fileURL: file)
        #expect(availability == .undetermined)
        #expect(availability.allowsDiffSelection)
    }

    @Test("git 管理外・扱えないリポジトリでは選べない", arguments: [
        GitRootLookup.notARepository,
        GitRootLookup.undetermined,
    ])
    func unavailableWhenGitCannotBeUsed(lookup: GitRootLookup) {
        let availability = GitDiffAvailability.make(
            baseDirectory: base(lookup), gitStatus: nil, fileURL: file
        )
        #expect(availability == .unavailable)
        #expect(!availability.allowsDiffSelection)
    }

    @Test("git リポジトリでも状態が未到着なら選べるまま")
    func undeterminedWhileStatusMissing() {
        let availability = GitDiffAvailability.make(
            baseDirectory: base(.root(URL(fileURLWithPath: "/repo"))), gitStatus: nil, fileURL: file
        )
        #expect(availability == .undetermined)
    }

    /// 状態はあるが、この行を答えられない範囲（別リポジトリ・サイドバー一覧外）。
    /// 「引けなかった＝変更なし」にすると、`degrade-on-facts` と同じ形で破れる。
    @Test("状態の適用範囲外なら選べるまま")
    func undeterminedOutsideStatusCoverage() {
        let availability = GitDiffAvailability.make(
            baseDirectory: base(.root(URL(fileURLWithPath: "/repo"))),
            gitStatus: status([:], root: "/other"),
            fileURL: file
        )
        #expect(availability == .undetermined)
    }

    @Test("変更のあるファイルは選べる")
    func changedWhenFileHasComparableChange() {
        let availability = GitDiffAvailability.make(
            baseDirectory: base(.root(URL(fileURLWithPath: "/repo"))),
            gitStatus: status([file.normalizedPathKey: GitFileStatus(worktreeChange: .modified)]),
            fileURL: file
        )
        #expect(availability == .changed)
        #expect(availability.allowsDiffSelection)
    }

    @Test("変更のないファイルは選べない")
    func unchangedWhenFileHasNoChange() {
        let availability = GitDiffAvailability.make(
            baseDirectory: base(.root(URL(fileURLWithPath: "/repo"))),
            gitStatus: status([:]),
            fileURL: file
        )
        #expect(availability == .unchanged)
        #expect(!availability.allowsDiffSelection)
    }

    /// 未追跡は HEAD に対応物が無く `GitFileDiff.untracked` になる。バッジは付くが
    /// 差分本文は出ないため、バッジの有無で判定すると「選べるのに何も起きない」が残る。
    @Test("未追跡ファイルはバッジが付いても差分は選べない")
    func unchangedForUntrackedFile() {
        let availability = GitDiffAvailability.make(
            baseDirectory: base(.root(URL(fileURLWithPath: "/repo"))),
            gitStatus: status([file.normalizedPathKey: GitFileStatus(isUntracked: true)]),
            fileURL: file
        )
        #expect(availability == .unchanged)
    }
}
