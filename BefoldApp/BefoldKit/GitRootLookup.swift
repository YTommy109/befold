import Foundation

/// リポジトリ検出の結果。「git 管理外」という確定した答えと「git を実行できず不明」を
/// 区別する(キャッシュしてよいのは前者だけで、後者を覚えると一時的な失敗が固定化する)。
///
/// **`URL?` へ潰さずにここまで運ぶ理由**: 潰すと「git 管理外」と「git リポジトリだが
/// befold では扱えない」が同じ nil になり、サイドバーが後者を「Plain folder」と
/// 事実と異なる表示にしてしまう(TASK-438.1)。表示側が 3 状態を区別できるよう、
/// 情報を捨てる位置を UI の手前まで下げる。
public enum GitRootLookup: Sendable, Equatable {
    case root(URL)
    case notARepository
    case undetermined

    /// 検出できたルート。管理外・判定不能はいずれも nil。
    public var foundRoot: URL? {
        guard case let .root(url) = self else { return nil }
        return url
    }
}
