import BefoldKit
import Foundation

/// 差分表示モードを選べるかを決める git 側の事実(TASK-438.2)。
///
/// ADR(libgit2 移行)の Fallback は縮退の 1 つとして「差分表示モードを選択不可にする」を
/// 挙げているが、`ViewerCapabilities` はファイル種別しか見ていなかった。結果、モードは
/// 選べて `ViewerDiffPresenter.displayableDiff(_:)` が黙って通常のソース表示へ戻していた。
///
/// ## 確定した否定の事実でだけ落とす
///
/// git の可用性もファイルの変更有無も非同期に届くため、素直に「分からない間は選べない」と
/// すると初期表示で無効→有効の入れ替わりが起きる。ここでは**未解決・範囲外は選べる側に
/// 倒し、確定した否定(`unavailable` / `unchanged`)でだけ落とす**。入れ替わりは
/// 「有効 → 無効」の 1 方向・1 回に限られる。
///
/// 「空だから無い」で判定しないこと(`degrade-on-facts`)。`FileListModel.gitStatus` の nil は
/// 「git 管理外」と「まだ届いていない」を兼ねるため、可用性は nil ではなく
/// `BaseDirectoryDescriptor.Kind`(= リポジトリを解決できたかという事実)から取る。
enum GitDiffAvailability: Equatable {
    /// まだ分からない(基準ディレクトリ未解決 / git 状態未到着 / 状態の適用範囲外)。
    case undetermined
    /// このディレクトリでは git を使えない(git 管理外、または befold が扱えないリポジトリ)。
    case unavailable
    /// git は使えるが、このファイルに**差分として出せる変更が無い**ことが確定した。
    /// 未変更のほか、未追跡(HEAD に対応物が無く `GitFileDiff.untracked` になる)もここ。
    case unchanged
    /// 差分として出せる変更がある。
    case changed

    /// 差分表示モードを選ばせてよいか。
    var allowsDiffSelection: Bool {
        switch self {
        case .undetermined, .changed: true
        case .unavailable, .unchanged: false
        }
    }

    /// サイドバーが持つ事実から導出する。git は呼ばない純粋な写像。
    ///
    /// - Parameters:
    ///   - baseDirectory: 基準ディレクトリの解決結果。nil は未解決。
    ///   - gitStatus: サイドバー 1 画面ぶんの git 状態。nil は未到着(または取得できない)。
    ///   - fileURL: 表示中のファイル。
    static func make(
        baseDirectory: BaseDirectoryDescriptor?,
        gitStatus: SidebarGitStatus?,
        fileURL: URL
    ) -> GitDiffAvailability {
        switch baseDirectory?.kind {
        case .plainFolder, .unusableRepository:
            return .unavailable
        case nil:
            return .undetermined
        case .gitRoot:
            break
        }
        // 状態が届いていない・この行を答えられない範囲なら「分からない」。
        // 変更が無いと言い切れるのは、範囲内で引いて何も無かったときだけ。
        guard let gitStatus, gitStatus.covers(fileURL.deletingLastPathComponent()) else {
            return .undetermined
        }
        guard let status = gitStatus.fileStatus(at: fileURL.normalizedPathKey) else { return .unchanged }
        // 未追跡は HEAD に対応物が無いため差分本文が出ない(`GitFileDiff.untracked`)。
        // バッジは付くが差分は描けないので、バッジの有無(`hasChange`)ではなく
        // 「HEAD と比べられる変更を持つか」で判定する。
        let hasComparableChange =
            status.indexChange != nil || status.worktreeChange != nil || status.branchChange != nil
        return hasComparableChange ? .changed : .unchanged
    }
}
