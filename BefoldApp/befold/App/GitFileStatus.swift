import Foundation

/// 1 ファイルの git 状態。`git status --porcelain=v2` の XY コード(X=index 側 / Y=worktree 側)と
/// untracked を、表示層がバッジ文字・色へ写像できる形で保持する。
///
/// 設計ドキュメントでは OptionSet を挙げていたが、バッジ文字は「index 側の変更種別(A/M/D…)」
/// そのものを出す仕様のため、フラグの集合では文字を復元できない。組み合わせ(staged かつ
/// unstaged など)は「どちらの辺が nil でないか」で表現でき、OptionSet と同じ判定ができる。
struct GitFileStatus: Equatable, Sendable {
    /// 変更の種別。porcelain の 1 文字コードに対応する。
    enum Change: Character, Sendable, CaseIterable {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case typeChanged = "T"
        case unmerged = "U"

        /// porcelain の XY コード 1 文字から変換する。`.`(変更なし)や未知のコードは nil。
        init?(porcelainCode: Character) {
            self.init(rawValue: porcelainCode)
        }
    }

    /// index 側(staged)の変更。未ステージのみなら nil。
    var indexChange: Change?
    /// worktree 側(unstaged)の変更。ステージ済みで作業ツリーが綺麗なら nil。
    var worktreeChange: Change?
    /// 未追跡ファイル(`?`)。
    var isUntracked: Bool = false
    /// base ブランチからのコミット済み変更(Phase 3 で設定する)。Phase 1 では常に false。
    var isBranchModified: Bool = false

    /// 何の変更も持たない(= バッジを出す理由がない)状態か。
    var isClean: Bool {
        indexChange == nil && worktreeChange == nil && !isUntracked && !isBranchModified
    }
}
