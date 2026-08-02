import BefoldKit
import SwiftUI

/// `GitFileStatus` をサイドバー行右端のバッジ(1 文字 + 色)へ写像する。
///
/// git を一切呼ばない純粋な写像なので、ここだけを単体テストで固定できる。
enum GitStatusBadge {
    /// バッジの色役割。実際の色は表示側(`GitStatusBadgeView`)が決める。
    enum Tint: Equatable, Sendable {
        case staged
        case unstaged
        case untracked
        case branchModified
    }

    /// バッジ 1 個分の見た目。
    struct Appearance: Equatable, Sendable {
        /// 表示する 1 文字。git の porcelain コード(A/M/D/?…)をそのまま出す。
        var character: Character
        /// 主色。
        var tint: Tint
        /// 副色。staged と unstaged が両立するときだけ入り、worktree 側の変更を示す。
        var accent: Tint?
        /// VoiceOver / ツールチップ用の説明キー。
        var descriptionKey: String.LocalizationValue
    }

    /// 状態からバッジを決める。バッジを出す理由が無ければ nil。
    ///
    /// staged と unstaged が両立するときは **文字を index 側で出し**、色は staged のまま
    /// アクセントで worktree 変更を示す(設計上の優先順位)。
    static func appearance(for status: GitFileStatus) -> Appearance? {
        if status.isUntracked {
            return Appearance(
                character: "?", tint: .untracked, accent: nil,
                descriptionKey: "sidebar.gitStatus.untracked"
            )
        }
        if let indexChange = status.indexChange {
            let hasWorktreeChange = status.worktreeChange != nil
            return Appearance(
                character: indexChange.rawValue,
                tint: .staged,
                accent: hasWorktreeChange ? .unstaged : nil,
                descriptionKey: hasWorktreeChange
                    ? "sidebar.gitStatus.stagedAndUnstaged" : "sidebar.gitStatus.staged"
            )
        }
        if let worktreeChange = status.worktreeChange {
            return Appearance(
                character: worktreeChange.rawValue, tint: .unstaged, accent: nil,
                descriptionKey: "sidebar.gitStatus.unstaged"
            )
        }
        if status.isBranchModified {
            return Appearance(
                character: GitFileStatus.Change.modified.rawValue, tint: .branchModified, accent: nil,
                descriptionKey: "sidebar.gitStatus.branchModified"
            )
        }
        return nil
    }
}

/// サイドバー行右端の git 状態バッジ。
struct GitStatusBadgeView: View {
    let appearance: GitStatusBadge.Appearance

    var body: some View {
        let description = Text(String(localized: appearance.descriptionKey, bundle: .l10n))
        HStack(spacing: 2) {
            if let accent = appearance.accent {
                // staged + unstaged。文字は index 側だが、worktree にも変更が残っていることを
                // 小さな点で示す(文字を 2 つ並べると行幅を食い、ファイル名の切り詰めが早まる)。
                Circle()
                    .fill(color(for: accent))
                    .frame(width: 4, height: 4)
            }
            Text(String(appearance.character))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color(for: appearance.tint))
        }
        .help(description)
        .accessibilityLabel(description)
    }

    private func color(for tint: GitStatusBadge.Tint) -> Color {
        switch tint {
        case .staged: .green
        case .unstaged: .orange
        case .untracked: .secondary
        case .branchModified: .blue
        }
    }
}
