import Foundation

/// サイドバーのファイル名フィルターで使う、`*`/`?` のみをサポートするワイルドカード照合。
/// `[...]` などその他の glob 構文や正規表現は特殊解釈せず、リテラル文字として扱う。
public enum WildcardMatcher {
    /// `pattern` を `name` に対して大文字小文字を無視した部分一致で評価する。
    /// 内部的に `pattern` を `*<pattern>*` へラップしてから照合するため、
    /// 呼び出し側で前後にワイルドカードを補う必要はない。
    public static func matches(pattern: String, in name: String) -> Bool {
        guard !pattern.isEmpty else { return true }
        guard let regex = try? NSRegularExpression(
            pattern: "^\(regexPattern(wrapping: pattern))$",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return false }
        let range = NSRange(name.startIndex..., in: name)
        return regex.firstMatch(in: name, range: range) != nil
    }

    /// `pattern` を `*<pattern>*` にラップしたうえで、`*`→`.*`、`?`→`.` に変換し、
    /// それ以外の正規表現メタ文字はすべてエスケープした正規表現文字列を返す。
    private static func regexPattern(wrapping pattern: String) -> String {
        "*\(pattern)*".map { character -> String in
            switch character {
            case "*": ".*"
            case "?": "."
            default: NSRegularExpression.escapedPattern(for: String(character))
            }
        }.joined()
    }
}
