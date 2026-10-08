import Foundation

/// 差分の比較基準(`GitComparisonTarget`)をサイドバーのメニューに出すときの文言と選択肢。
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
}
