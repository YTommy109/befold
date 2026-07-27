import Foundation

/// Quick Open の入力文字列を、どの探し方で候補を出すかに分類する純粋ロジック。
///
/// 分類だけを担い、解決も検索も行わない。パスモードの解決は `TrackedPathResolver`、
/// fuzzy 検索は `FuzzyMatcher` がそれぞれ受け持つ。
public enum QuickOpenQuery {
    /// 入力の分類結果。付随する文字列は前後の空白を落とした後の値。
    public enum Kind: Equatable, Sendable {
        /// 空入力。履歴とブックマークを出す。
        case empty
        /// `/` `~` `.` 始まり。パスとして解決する。
        case path(String)
        /// それ以外。候補集合に対して fuzzy 検索する。
        case fuzzy(String)
    }

    /// パスモードへ倒す先頭文字。`~` は展開対象、`.` は `./` `../` と隠しファイル名の双方を含む。
    private static let pathPrefixes: Set<Character> = ["/", "~", "."]

    /// 前後の空白は入力として意味を持たないため落としてから分類する。
    /// パスの途中や内部の空白（`~/My Documents`）はそのまま残す。
    public static func classify(_ input: String) -> Kind {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return .empty }
        return pathPrefixes.contains(first) ? .path(trimmed) : .fuzzy(trimmed)
    }
}
