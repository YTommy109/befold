import Foundation

/// CSV/TSV テーブル表示で負の数をどう見せるか(アプリ全体の設定)。
///
/// 会計慣習の ▲ 表記・赤字は金額に対するものだが、**どの列が金額かは推測しない**。
/// ヘッダー名の肯定側マッチ(`price` / `金額` 等)は網羅不能で、当てにすると誤爆を
/// 増やす方向にしか働かないため(列判定が肯定側マッチを採らないのと同じ理由)。
/// 代わりに、この設定そのものが意図を運ぶと考える。既定の `plain` から変える
/// ユーザーは、自分の扱うファイルが会計データであることを宣言している。
/// したがって適用範囲は「コードとみなせない量の列」すべてでよい。
///
/// rawValue は JS へそのまま注入され、`viewer-src/csv-number-format.ts` の
/// `CSV_NEGATIVE_STYLES` と一致していなければならない。**この型が唯一の情報源**で、
/// 一致は `CsvNegativeStyleContractTests` が viewer-bundle.js を読んで検証する。
public enum CsvNegativeStyle: String, CaseIterable, Sendable {
    /// 通常表記(-1,234)。
    case plain
    /// ▲ 表記(▲1,234)。符号そのものを置き換える。
    case triangle
    /// 赤字(-1,234 を赤で表示)。
    case red
    /// ▲ 表記 + 赤字。
    case triangleRed

    /// 未知の文字列(古い UserDefaults の値など)は既定へ倒す。
    public static func from(rawValue: String?) -> CsvNegativeStyle {
        guard let rawValue, let style = CsvNegativeStyle(rawValue: rawValue) else { return .plain }
        return style
    }
}
