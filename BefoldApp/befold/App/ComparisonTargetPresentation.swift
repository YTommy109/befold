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
    ///
    /// **現在の基準は常に含める。** 窓の基準は選んだ後に別リポジトリへ移っても戻らないため、
    /// 落とすとサイドバーの Picker は選択無しになり、表示メニューは現在の項目ごと消える
    /// (差分とバッジは現在の基準で取れ続けるので、UI と実体がずれる)。
    /// サイドバーと表示メニューはどちらもこの 1 本から選択肢を得る。
    static func selectableTargets(
        current: GitComparisonTarget, resolution: GitComparisonResolution?
    ) -> [GitComparisonTarget] {
        let showsStack = resolution?.parentDiffersFromDefault ?? false
        return GitComparisonTarget.allCases.filter { $0 == current || $0 != .defaultBranch || showsStack }
    }

    /// メニュー項目のタグ。`NSMenuItem.tag` の既定値 0 と区別するため 1 から振る。
    static func menuItemTag(for target: GitComparisonTarget) -> Int {
        // 列挙漏れは静かに別の基準へ写さず落とす(`allCases` は自動合成なので到達しない)。
        GitComparisonTarget.allCases.firstIndex(of: target)! + 1
    }

    /// タグから基準を復元する。該当が無ければ nil(他の項目のタグ)。
    static func target(menuItemTag tag: Int) -> GitComparisonTarget? {
        GitComparisonTarget.allCases.first { menuItemTag(for: $0) == tag }
    }
}

/// View メニューの比較基準項目が読む窓の状態。選択肢はサイドバーの▾と同じ
/// `selectableTargets(current:resolution:)` から得る。
struct ComparisonMenuState: Equatable {
    let current: GitComparisonTarget
    let selectable: [GitComparisonTarget]
    /// 選べるか。git 管理外(`FileListModel.canFilterChangedFiles` が false)では比較する先が無い。
    /// さらにサイドバーを持たない窓(スライド)では、基準を操作するコントロールの置き場自体が
    /// 無いので `kind.allowsSidebar` でも塞ぐ。サイドバーの▾はサイドバーの中にあるため
    /// `canFilterChangedFiles` だけを見ればよく、この条件はメニュー側だけが持つ。
    let isAvailable: Bool
}
