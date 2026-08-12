import Foundation

/// サイドバーの git 状態を **受け付けるか / 保留するか / 捨てるか** を決める調停器
/// (ADR 0003 / TASK-443)。
///
/// 取得そのものは `SidebarGitStatusCoordinator` が担い、この型は取得結果を持ち込まれた
/// ときの可否判定だけを持つ。判定の材料は 2 つ——発行順序(sequence)と、手元の一覧が
/// どのディレクトリのものか——で、どちらも一覧の保持とは別の不変条件なので
/// `FileListModel` から切り出してある。
///
/// **この型は状態そのもの(`SidebarGitStatus`)を保持しない。** 反映すべき値は
/// `Decision.apply` で呼び出し元へ返し、`FileListModel` の観測対象プロパティへ書かせる。
/// 保留・発行順序まで観測対象の struct にまとめてしまうと、「保留しただけで画面は
/// 変わらない」場合にも書き込みが観測を発火し、TASK-278 が潰した「1 回の移動で
/// ツールバー再同期が何度も走る」と同型の回帰になる。
struct FileListGitStatusGate {
    /// 調停の結論。
    enum Decision: Equatable {
        /// 古い発行順序なので無視した。呼び出し元は `.git/index` 監視を張り直さない。
        case ignored
        /// 対応する一覧がまだ届いていないので保留した。受け付けた扱いにする。
        case deferred
        /// いま反映してよい。`FileListModel` はこの値を観測対象のプロパティへ書く。
        case apply(SidebarGitStatus?)
    }

    /// 直近に**反映を受け付けた** git 状態の発行順序。反映の可否はこれとの比較で決める。
    /// 「最新の発行と一致」で判定すると、一覧と対で取った結果を捨てないために sequence を
    /// 強制的に進める必要が生じ、後から始まった取得の新しい結果を古いスナップショットで
    /// 上書きしてしまう。「これより新しい sequence なら受け付ける」なら、結合取得も後発の
    /// 単発取得も「最後に発行された取得が勝つ」不変条件のまま扱える。
    private var appliedSequence = 0

    /// まだ手元に一覧が無いディレクトリの git 状態。届いた順に入れてしまうと、画面に出ている
    /// 一覧に対応する状態が失われて絞り込みが一瞬外れるため、一覧が届くまでここで待たせる。
    ///
    /// **状態が nil(git 管理外・取得失敗)でも「どのディレクトリの結論か」を持たせる**のが
    /// 要点で、これが無いと非 git フォルダーへ移動したときに「まだ届いていない」と区別できない。
    private var pending: Pending?

    private struct Pending {
        let directoryKey: String
        let status: SidebarGitStatus?
    }

    /// `directoryKey` の git 状態を持ち込む。発行順序(recency)とディレクトリ対付けの
    /// 両方をここで一括判定する。呼び出し元は sequence の採番だけを担い、可否には関与しない。
    ///
    /// ディレクトリ対付け: 手元の一覧がまだ別のディレクトリのものなら、その一覧が届くまで
    /// 保留する。移動先の状態を先に入れると、画面に出ている一覧(移動元)と突き合わせられなく
    /// なって絞り込みが外れ、全件が一瞬表示される。実測では `.git/index` 監視や再読込を契機と
    /// する単独の取得が、移動先を対象に一覧より先に着地していた(TASK-293)。
    ///
    /// - Parameter entriesDirectoryKey: 手元の一覧を列挙したディレクトリの正規化キー。
    mutating func accept(
        _ status: SidebarGitStatus?,
        forDirectoryKey directoryKey: String,
        sequence: Int,
        entriesDirectoryKey: String
    ) -> Decision {
        guard sequence > appliedSequence else { return .ignored }
        appliedSequence = sequence
        guard directoryKey == entriesDirectoryKey else {
            pending = Pending(directoryKey: directoryKey, status: status)
            return .deferred
        }
        pending = nil
        return .apply(status)
    }

    /// 一覧が入れ替わったときに呼ぶ。その一覧のディレクトリに対する保留があれば
    /// `.apply` を返す。無ければ `.ignored`(反映するものが無い)。
    mutating func promote(entriesDirectoryKey: String) -> Decision {
        guard let pending, pending.directoryKey == entriesDirectoryKey else { return .ignored }
        self.pending = nil
        return .apply(pending.status)
    }

    /// `sequence` 以前に発行されたすべての取得結果を無効化する。ウィンドウを閉じるときに呼ぶ
    /// (TASK-300)。キャンセルは協調的で、走り出した subprocess は完了して結果を返しうる。
    /// 反映済み sequence を発行済みの先頭へ揃えておかないと、その結果が反映ガードを通り抜け、
    /// 閉じたウィンドウのために `.git/index` 監視を張り直してしまう。
    mutating func invalidate(upTo sequence: Int) {
        appliedSequence = max(appliedSequence, sequence)
    }
}
