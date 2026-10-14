import Foundation

/// 「この文書のこの行を先頭へ出す」という 1 回きりの要求(CLI の `--line`)。
///
/// `serial` は要求ごとに増える通し番号で、描画面への配達を一度きりにするために使う。
/// 値の同一性で重複を判定すると、同じ行を続けて指定した 2 回目が「配達済み」として
/// 握り潰される。
public struct LineRevealRequest: Equatable, Sendable {
    public let serial: Int
    /// 対象文書の `normalizedPathKey`。JS 側は採用済みの文書パスと照合し、別の文書には適用しない。
    public let path: String
    /// 1 始まりの行番号。
    public let line: Int

    public init(serial: Int, path: String, line: Int) {
        self.serial = serial
        self.path = path
        self.line = line
    }
}
