@testable import befold
import Testing

/// `GitFileStatus` → バッジ(文字・色)の写像。表示層の純粋関数なので git も UI も要らない。
struct GitStatusBadgeTests {
    @Test("staged は index 側のコードを緑で出す")
    func stagedUsesIndexCode() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(for: GitFileStatus(indexChange: .added, worktreeChange: nil))
        )

        #expect(appearance.character == "A")
        #expect(appearance.tint == .staged)
        #expect(appearance.accent == nil)
    }

    @Test("unstaged のみなら worktree 側のコードを橙で出す")
    func unstagedUsesWorktreeCode() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(for: GitFileStatus(indexChange: nil, worktreeChange: .deleted))
        )

        #expect(appearance.character == "D")
        #expect(appearance.tint == .unstaged)
        #expect(appearance.accent == nil)
    }

    /// 設計上の優先順位: 文字は index 側、worktree の変更は色(アクセント)で示す。
    @Test("staged と unstaged が両立する場合は index 側の文字を優先しアクセントで worktree を示す")
    func prefersIndexCodeWhenBothSidesChanged() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(for: GitFileStatus(indexChange: .added, worktreeChange: .modified))
        )

        #expect(appearance.character == "A")
        #expect(appearance.tint == .staged)
        #expect(appearance.accent == .unstaged)
    }

    @Test("untracked は ? を灰で出し、index/worktree より優先する")
    func untrackedUsesQuestionMark() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(
                for: GitFileStatus(indexChange: nil, worktreeChange: nil, isUntracked: true)
            )
        )

        #expect(appearance.character == "?")
        #expect(appearance.tint == .untracked)
    }

    @Test("branchModified 単独は青の M を出す")
    func branchModifiedUsesBlueModified() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(
                for: GitFileStatus(
                    indexChange: nil, worktreeChange: nil, isUntracked: false, isBranchModified: true
                )
            )
        )

        #expect(appearance.character == "M")
        #expect(appearance.tint == .branchModified)
    }

    /// worktree に変更があるファイルは、ブランチ内変更も兼ねていても
    /// 「今このファイルに未コミットの変更がある」ほうを優先して出す(Phase 3 との整合)。
    @Test("worktree 変更は branchModified より優先される")
    func worktreeChangeWinsOverBranchModified() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(
                for: GitFileStatus(
                    indexChange: nil, worktreeChange: .modified, isUntracked: false, isBranchModified: true
                )
            )
        )

        #expect(appearance.tint == .unstaged)
    }

    @Test("変更が無ければバッジを出さない")
    func noBadgeForCleanStatus() {
        #expect(GitStatusBadge.appearance(for: GitFileStatus()) == nil)
    }

    // MARK: - フォルダー行

    /// フォルダーのバッジは配下の集約なので、ファイル行の A/M/D/? とは別の記号にする。
    @Test("フォルダーのバッジはファイル行と区別できる記号を使う")
    func folderBadgeUsesDistinctSymbol() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(forFolder: GitFolderStatus(hasUnstaged: true))
        )

        #expect(appearance.character == "•")
        #expect(appearance.tint == .unstaged)
        #expect(appearance.accent == nil)
    }

    @Test("配下に変更が無いフォルダーはバッジを出さない")
    func noFolderBadgeWithoutChanges() {
        #expect(GitStatusBadge.appearance(forFolder: GitFolderStatus()) == nil)
    }

    /// 混在時は優先順位の高い種別を主色にし、次点をアクセントで示す(ファイル行と同じ語彙)。
    @Test("複数種類が混在するフォルダーは主色と次点のアクセントで示す")
    func folderBadgeShowsSecondTintAsAccent() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(
                forFolder: GitFolderStatus(hasStaged: true, hasUnstaged: true, hasUntracked: true)
            )
        )

        #expect(appearance.tint == .staged)
        #expect(appearance.accent == .unstaged)
    }

    @Test(
        "フォルダーの主色は staged > unstaged > untracked > branchModified の順で決まる",
        arguments: [
            (GitFolderStatus(hasStaged: true, hasBranchModified: true), GitStatusBadge.Tint.staged),
            (GitFolderStatus(hasUnstaged: true, hasUntracked: true), .unstaged),
            (GitFolderStatus(hasUntracked: true, hasBranchModified: true), .untracked),
            (GitFolderStatus(hasBranchModified: true), .branchModified),
        ]
    )
    func folderTintPrecedence(status: GitFolderStatus, expected: GitStatusBadge.Tint) throws {
        #expect(try #require(GitStatusBadge.appearance(forFolder: status)).tint == expected)
    }

    @Test("単一種類のフォルダーにはアクセントを付けない")
    func noAccentForSingleKind() throws {
        let appearance = try #require(
            GitStatusBadge.appearance(forFolder: GitFolderStatus(hasUntracked: true))
        )

        #expect(appearance.accent == nil)
    }
}
