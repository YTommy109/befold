import Foundation

/// fuzzy 一致した 1 件。`text` は照合対象に渡した文字列そのもの。
public struct FuzzyMatch: Equatable, Sendable {
    public let text: String
    public let score: Int

    public init(text: String, score: Int) {
        self.text = text
        self.score = score
    }
}

/// 入力を部分列として照合し、順位付きの複数候補を返す。
///
/// 既存の `SuffixPathMatcher` は「構成要素単位のサフィックス一致で最良 1 件」を返す設計で、
/// 候補リストの表示には使えない。文書内リンク解決の挙動を変えないため照合規則は共有せず、
/// Quick Open 用の照合をここに独立して置く。
///
/// スコアの絶対値に意味はない。加点の大小関係が候補の並び順を決めるためだけに存在する。
public enum FuzzyMatcher {
    /// 一致 1 文字あたりの基礎点。
    private static let matchBase = 10
    /// 直前の一致文字に続けて一致した場合の加点。断片をまとめて打った入力を上位に出す。
    private static let consecutiveBonus = 15
    /// 単語境界(先頭 / `/` `_` `-` `.` ` ` の直後 / キャメルケース境界)での一致の加点。
    private static let boundaryBonus = 12
    /// ファイル名部分だけで一致が成立した場合の加点。
    /// ディレクトリ名に散らばって一致しただけの候補より必ず上位へ来るよう、
    /// 現実的な入力長で他の加点の合計を上回る大きさにしている。
    private static let filenameBonus = 1000

    /// 単語境界と見なす区切り文字。
    private static let separators: Set<Character> = ["/", "_", "-", ".", " "]

    /// `query` が `text` に部分列として現れるなら、最良の対応付けのスコアを返す。
    /// 現れないなら nil。空の入力は「絞り込みなし」としてスコア 0 で一致する。
    ///
    /// 入力に `/` を含む場合はパス全体に照合する。含まない場合はファイル名部分を優先し、
    /// ファイル名だけで一致するならそちらを採って加点する。
    public static func score(query: String, text: String) -> Int? {
        let queryCharacters = Array(query)
        guard !queryCharacters.isEmpty else { return 0 }

        let textCharacters = Array(text)
        if let filenameScore = filenameOnlyScore(query: queryCharacters, text: textCharacters) {
            return filenameScore + filenameBonus
        }
        return bestAlignmentScore(query: queryCharacters, text: textCharacters)
    }

    /// ファイル名部分だけで一致が成立するならそのスコア。
    /// 入力が `/` を含む場合はパス全体で照合すべきなので、ここでは常に nil を返す。
    private static func filenameOnlyScore(query: [Character], text: [Character]) -> Int? {
        guard !query.contains("/") else { return nil }
        guard let filenameStart = filenameStartIndex(of: text) else { return nil }
        return bestAlignmentScore(query: query, text: Array(text[filenameStart...]))
    }

    /// 一致した候補をスコア降順、同点は `text` 昇順で返す。
    /// 同点の並びを固定することで、同じ入力に対して常に同じ順序になる。
    public static func rank(query: String, texts: [String], limit: Int? = nil) -> [FuzzyMatch] {
        var matches: [FuzzyMatch] = []
        for text in texts {
            guard let score = score(query: query, text: text) else { continue }
            matches.append(FuzzyMatch(text: text, score: score))
        }
        matches.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.text < rhs.text : lhs.score > rhs.score
        }
        guard let limit else { return matches }
        return Array(matches.prefix(limit))
    }

    // MARK: - Private

    /// 最後の `/` の次の位置。`/` が無ければ先頭。構成要素を持たない文字列では nil。
    private static func filenameStartIndex(of text: [Character]) -> Int? {
        guard !text.isEmpty else { return nil }
        guard let lastSlash = text.lastIndex(of: "/") else { return 0 }
        let start = lastSlash + 1
        return start < text.count ? start : nil
    }

    /// 部分列としての対応付けのうち最良のスコア。部分列でなければ nil。
    ///
    /// 貪欲に左から詰めると「後ろに出てくる連続一致」を取り逃すため、
    /// query × text の動的計画法で最良の対応付けを選ぶ。text 長に比例した
    /// 事前の部分列判定で大半の候補を弾いてから DP に入る。
    private static func bestAlignmentScore(query: [Character], text: [Character]) -> Int? {
        guard isSubsequence(query: query, text: text) else { return nil }

        let folded = text.map { Character($0.lowercased()) }
        let foldedQuery = query.map { Character($0.lowercased()) }
        let boundaries = (0 ..< text.count).map { isWordBoundary(text, at: $0) }

        // previous[j] = query の 1 つ前までを text[j] で終える形に対応付けた最良スコア。
        var previous = [Int?](repeating: nil, count: text.count)
        var current = [Int?](repeating: nil, count: text.count)

        for (queryIndex, queryCharacter) in foldedQuery.enumerated() {
            // prefixMaximum[j] = previous[0...j] の最大値。非連続の対応付けを O(1) で引くため。
            var prefixMaximum = [Int?](repeating: nil, count: text.count)
            if queryIndex > 0 {
                var running: Int?
                for index in 0 ..< text.count {
                    running = maximum(running, previous[index])
                    prefixMaximum[index] = running
                }
            }

            for textIndex in 0 ..< text.count {
                guard folded[textIndex] == queryCharacter else {
                    current[textIndex] = nil
                    continue
                }
                let characterScore = matchBase + (boundaries[textIndex] ? boundaryBonus : 0)

                guard queryIndex > 0 else {
                    current[textIndex] = characterScore
                    continue
                }
                var best: Int?
                // 間を空けて続ける場合。直前の一致は textIndex - 2 以前で終わっている。
                if textIndex >= 2, let gapped = prefixMaximum[textIndex - 2] {
                    best = gapped + characterScore
                }
                // 直前の文字に続けて一致する場合。
                if textIndex >= 1, let consecutive = previous[textIndex - 1] {
                    best = maximum(best, consecutive + characterScore + consecutiveBonus)
                }
                current[textIndex] = best
            }
            swap(&previous, &current)
        }
        return previous.compactMap(\.self).max()
    }

    /// `query` が `text` の部分列か(大文字小文字を無視)。
    private static func isSubsequence(query: [Character], text: [Character]) -> Bool {
        var queryIndex = 0
        for character in text {
            guard queryIndex < query.count else { break }
            if String(character).lowercased() == String(query[queryIndex]).lowercased() {
                queryIndex += 1
            }
        }
        return queryIndex == query.count
    }

    /// 先頭、区切り文字の直後、または小文字/数字から大文字へ変わる位置か。
    private static func isWordBoundary(_ text: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = text[index - 1]
        if separators.contains(previous) { return true }
        return (previous.isLowercase || previous.isNumber) && text[index].isUppercase
    }

    private static func maximum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }
}
