import Foundation

/// 差分の比較基準(`GitComparisonTarget`)をツールバーに出すときの文言と選択肢。
///
/// git は呼ばない純粋な写像。基準ブランチ名や「スタック全体」を出してよいかは、
/// 取得済みの `GitComparisonResolution` から読む(メニューを開く瞬間に git を触らない)。
enum ComparisonTargetPresentation {
    /// メニュー項目の見出し(「このブランチの変更」など)。
    static func title(for target: GitComparisonTarget) -> String {
        switch target {
        case .parentBranch: String(localized: "toolbar.mode.diff.target.parentBranch", bundle: .l10n)
        case .defaultBranch: String(localized: "toolbar.mode.diff.target.defaultBranch", bundle: .l10n)
        case .head: String(localized: "toolbar.mode.diff.target.head", bundle: .l10n)
        }
    }

    /// 選べる基準。「スタック全体の変更」は親ブランチがデフォルトブランチと異なるときだけ出す
    /// (同じなら「このブランチの変更」と同じ結果になり、選ぶ意味が無い)。
    static func selectableTargets(resolution: GitComparisonResolution?) -> [GitComparisonTarget] {
        let showsStack = resolution?.parentDiffersFromDefault ?? false
        return GitComparisonTarget.allCases.filter { $0 != .defaultBranch || showsStack }
    }

    /// ポップアップに出すラベル。解決された基準ブランチ名("main から")を出し、
    /// `.head` は "HEAD から"。解決前・解決できないときは基準の見出しで代える。
    /// `isUnchanged` は差分が空(通常のソース表示へ戻っている)ときで、「(変更なし)」を足す。
    static func label(
        target: GitComparisonTarget, resolution: GitComparisonResolution?, isUnchanged: Bool
    ) -> String {
        let base = if target == .head {
            String(format: String(localized: "toolbar.mode.diff.base", bundle: .l10n), "HEAD")
        } else if let name = resolution?.baseBranch {
            String(format: String(localized: "toolbar.mode.diff.base", bundle: .l10n), name)
        } else {
            title(for: target)
        }
        return isUnchanged
            ? String(format: String(localized: "toolbar.mode.diff.base.unchanged", bundle: .l10n), base)
            : base
    }
}
