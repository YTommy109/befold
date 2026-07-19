import Foundation

/// loadMoreLines() の結果。contentRevision は追記後の世代番号で、呼び出し側が
/// 描画済みキャッシュを同期し直後の全文 render 誤爆を防ぐために使う。
public struct LoadMoreLinesResult: Equatable, Sendable {
    public let chunk: String
    public let isTruncated: Bool
    public let lineCount: Int
    public let contentRevision: Int
    /// セッション途中のチャンク読込がエラーで打ち切られた場合 true。
    /// isTruncated は true のまま維持され(表示済みが全体ではないことを示すため)、
    /// このフラグでバナーを「正常な段階読込」ではなく「読込エラー」として区別する。
    public let loadFailed: Bool

    public init(chunk: String, isTruncated: Bool, lineCount: Int, contentRevision: Int, loadFailed: Bool) {
        self.chunk = chunk
        self.isTruncated = isTruncated
        self.lineCount = lineCount
        self.contentRevision = contentRevision
        self.loadFailed = loadFailed
    }
}
