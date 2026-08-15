import Foundation

/// ソース表示へ重ねる git 差分の、取得結果としての状態。
///
/// 「取得が飛行中でまだ確定していない(pending)」と「確定して描ける差分が無い
/// (unavailable)」を型で区別する。`String?` で持つと両方が nil に潰れ、
/// 差分表示モードへ切り替えた直後に差分なしのプレーンなソース表示が中間状態として
/// 一瞬描画される(TASK-407)。
enum ViewerDiffContent: Equatable {
    /// 確定: 差分として描ける本文が無い(変更なし・未追跡・取得失敗・機能無効を含む)。
    /// 表示は通常のソース表示になる。
    case unavailable
    /// 取得が飛行中で、差分の有無がまだ確定していない。レンダラ境界では
    /// `DiffState.pending` に写り、確定までモード切替だけの再描画が見送られる。
    case pending
    /// 確定: 差分として描ける本文(unified diff)。
    case diff(String)

    /// 確定した差分本文。未確定(.pending)・差分なし(.unavailable)は nil。
    var text: String? {
        guard case let .diff(text) = self else { return nil }
        return text
    }
}
