import Foundation
import libgit2

/// 1 ファイルの git 状態。git の変更種別(X=index 側 / Y=worktree 側)と untracked を、
/// 表示層がバッジ文字・色へ写像できる形で保持する。
///
/// 設計ドキュメントでは OptionSet を挙げていたが、バッジ文字は「index 側の変更種別(A/M/D…)」
/// そのものを出す仕様のため、フラグの集合では文字を復元できない。組み合わせ(staged かつ
/// unstaged など)は「どちらの辺が nil でないか」で表現でき、OptionSet と同じ判定ができる。
struct GitFileStatus: Equatable, Sendable {
    /// 変更の種別。
    ///
    /// rawValue は `git status --short` / `--name-status` が出す 1 文字コードで、
    /// **そのままバッジ文字として表示する**(`GitStatusBadge`)。利用者が git の出力で
    /// 見慣れた語彙をそのまま使うための rawValue であって、内部表現の都合ではない。
    enum Change: Character, Sendable, CaseIterable {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case typeChanged = "T"
        case unmerged = "U"

        /// libgit2 の差分種別から変換する。バッジを出す理由にならないもの
        /// (変更なし・ignored・untracked・読めない)は nil。
        ///
        /// untracked が nil なのは、`GitFileStatus` が untracked を種別ではなく
        /// `isUntracked` の別フィールドで持つため(バッジ文字が `?` で、種別コードではない)。
        ///
        /// git の変更語彙と befold の種別を結ぶ唯一の写像。status・branch diff・
        /// (TASK-435.4 以降の)差分ビューアがここを共有する。
        init?(delta: git_delta_t) {
            switch delta {
            case GIT_DELTA_ADDED: self = .added
            case GIT_DELTA_MODIFIED: self = .modified
            case GIT_DELTA_DELETED: self = .deleted
            case GIT_DELTA_RENAMED: self = .renamed
            case GIT_DELTA_COPIED: self = .copied
            case GIT_DELTA_TYPECHANGE: self = .typeChanged
            case GIT_DELTA_CONFLICTED: self = .unmerged
            default: return nil
            }
        }
    }

    /// index 側(staged)の変更。未ステージのみなら nil。
    var indexChange: Change?
    /// worktree 側(unstaged)の変更。ステージ済みで作業ツリーが綺麗なら nil。
    var worktreeChange: Change?
    /// 未追跡ファイル(`?`)。
    var isUntracked: Bool = false
    /// base ブランチからのコミット済み変更の種別。ブランチ内で変わっていなければ nil。
    ///
    /// 真偽値ではなく種別を持つ。真偽値だと表示側が「変更あり」を 1 種類の文字へ
    /// 決め打ちするしかなく、ブランチで**追加**したファイルまで M になっていた(TASK-344)。
    var branchChange: Change?

    /// 何の変更も持たない(= バッジを出す理由がない)状態か。
    var isClean: Bool {
        indexChange == nil && worktreeChange == nil && !isUntracked && branchChange == nil
    }
}
