import Foundation

// MARK: - git 差分

/// 差分表示の JS 呼び出しは本体から分けている(ViewerBridge.swift の行数上限)。
public extension ViewerBridge {
    /// git 差分表示のレイアウト。
    enum DiffLayout: String, Sendable, CaseIterable {
        /// 1 列に追加・削除を並べる。
        case inline
        /// 左右に分割して並べる。
        case sideBySide = "side-by-side"
    }

    /// setDiff(text) 呼び出しを組み立てる。
    /// 差分本文は git の出力そのものでユーザーが書いた内容を含むため、
    /// render と同じく JSON エンコードでエスケープする(JS インジェクション対策)。
    /// nil(差分なし)は null を渡して JS 側の差分表示を解除する。
    static func diffScript(_ text: String?) -> String {
        guard let text, let literal = jsonLiteral(text) else { return "setDiff(null)" }
        return "setDiff(\(literal))"
    }

    /// setDiffLayout(layout) 呼び出しを組み立てる。
    static func diffLayoutScript(_ layout: DiffLayout) -> String {
        "setDiffLayout('\(layout.rawValue)')"
    }
}
