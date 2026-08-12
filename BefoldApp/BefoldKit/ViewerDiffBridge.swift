import Foundation

/// git 差分表示の JS 呼び出しを組み立てる。
///
/// 差分は「ソース表示へ重ねる」独立した表示機能で、viewer 側も setDiff / setDiffLayout の
/// 2 関数で完結している。`ViewerBridge` の行数上限を避けるための extension だったものを、
/// 独立した型へ昇格させた(TASK-444)。
public enum ViewerDiffBridge {
    /// git 差分表示のレイアウト。
    public enum Layout: String, Sendable, CaseIterable {
        /// 1 列に追加・削除を並べる。
        case inline
        /// 左右に分割して並べる。
        case sideBySide = "side-by-side"
    }

    /// setDiff(text) 呼び出しを組み立てる。
    /// 差分本文は git の出力そのものでユーザーが書いた内容を含むため、
    /// render と同じく JSON エンコードでエスケープする(JS インジェクション対策)。
    /// nil(差分なし)は null を渡して JS 側の差分表示を解除する。
    public static func textScript(_ text: String?) -> String {
        guard let text, let literal = ViewerBridge.jsonLiteral(text) else { return "setDiff(null)" }
        return "setDiff(\(literal))"
    }

    /// setDiffLayout(layout) 呼び出しを組み立てる。
    public static func layoutScript(_ layout: Layout) -> String {
        "setDiffLayout('\(layout.rawValue)')"
    }
}
