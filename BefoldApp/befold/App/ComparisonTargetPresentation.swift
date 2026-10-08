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

    /// メニュー項目のタグ。`NSMenuItem.tag` の既定値 0 と区別するため 1 から振る。
    static func menuItemTag(for target: GitComparisonTarget) -> Int {
        (GitComparisonTarget.allCases.firstIndex(of: target) ?? 0) + 1
    }

    /// タグから基準を復元する。該当が無ければ nil(他の項目のタグ)。
    static func target(menuItemTag tag: Int) -> GitComparisonTarget? {
        GitComparisonTarget.allCases.first { menuItemTag(for: $0) == tag }
    }
}

/// View メニューの比較基準項目が読む窓の状態。サイドバーの▾と同じ選択肢・同じ git 判定
/// (`FileListModel.canFilterChangedFiles`)を使い、メニュー側に別の条件を持たない。
struct ComparisonMenuState: Equatable {
    let current: GitComparisonTarget
    let selectable: [GitComparisonTarget]
    /// git 管理外では選べない(比較する先が無い)。
    let isAvailable: Bool
}
