import Foundation

/// 入力を部分列として照合し、候補ごとのスコアを返す。
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
        let foldedQuery = caseFolded(queryCharacters)
        if let filenameScore = filenameOnlyScore(
            query: queryCharacters, foldedQuery: foldedQuery, text: textCharacters
        ) {
            return filenameScore + filenameBonus
        }
        return bestAlignmentScore(foldedQuery: foldedQuery, text: textCharacters)
    }

    /// ファイル名部分だけで一致が成立するならそのスコア。
    /// 入力が `/` を含む場合はパス全体で照合すべきなので、ここでは常に nil を返す。
    private static func filenameOnlyScore(
        query: [Character], foldedQuery: [Character], text: [Character]
    ) -> Int? {
        guard !query.contains("/") else { return nil }
        guard let filenameStart = filenameStartIndex(of: text) else { return nil }
        return bestAlignmentScore(foldedQuery: foldedQuery, text: Array(text[filenameStart...]))
    }

    // MARK: - Private

    /// 大文字小文字を無視するための唯一の畳み込み。部分列判定と DP の双方がこの結果を使い、
    /// 照合ごとに文字単位で `lowercased()` の String を作り直す割り当てを避ける。
    /// `Character($0.lowercased())` は結果が 1 書記素でないと trap するため、
    /// 先頭書記素を採り(無ければ元の文字)安全側に倒す。
    private static func caseFolded(_ characters: [Character]) -> [Character] {
        characters.map { $0.lowercased().first ?? $0 }
    }

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
    private static func bestAlignmentScore(foldedQuery: [Character], text: [Character]) -> Int? {
        // fold は 1 度だけ。部分列判定と DP のマッチング比較の双方でこの配列を使う。
        let folded = caseFolded(text)
        guard isSubsequence(query: foldedQuery, text: folded) else { return nil }

        // 単語境界(キャメルケース)判定は大小を見るため、畳み込み前の text を使う。
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

    /// `query` が `text` の部分列か。両者は `caseFolded` 済みで渡されるため、
    /// ここでは文字を直接比較するだけ(照合ごとの String 生成をしない)。
    private static func isSubsequence(query: [Character], text: [Character]) -> Bool {
        var queryIndex = 0
        for character in text {
            guard queryIndex < query.count else { break }
            if character == query[queryIndex] {
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
