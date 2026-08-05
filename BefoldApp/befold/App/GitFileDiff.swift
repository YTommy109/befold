import Foundation

/// 1 ファイル分の差分取得結果。
///
/// 「差分本文が無い」理由は複数あり、呼び出し側はそれぞれで違う表示をする必要がある
/// (未追跡は全行追加として見せられる、バイナリは差分を出せない、変更なしは通常のソース表示へ戻る)。
/// 空文字列 1 つで表すと、`degrade-on-facts` と同じ形で理由が潰れるため列挙で返す。
enum GitFileDiff: Equatable, Sendable {
    /// unified diff の本文。
    case diff(String)
    /// 追跡されており、HEAD と一致する(差分なし)。
    case noChanges
    /// git 管理下だが未追跡。HEAD に対応物が無いため diff は空になる。
    case untracked
    /// バイナリ差分。git が本文を出さない(または UTF-8 として読めない)。
    case binary
    /// 差分が大きすぎて描画に載せない。
    case tooLarge(byteCount: Int)
    /// リポジトリにコミットが 1 つも無い(HEAD が解決できない)。
    case noCommits
    /// git 管理外。
    case notInRepository
}
