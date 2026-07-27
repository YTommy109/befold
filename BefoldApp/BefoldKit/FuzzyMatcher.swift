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
        if let filename = filenameAlignment(
            query: queryCharacters, foldedQuery: foldedQuery, text: textCharacters
        ) {
            return filename.score + filenameBonus
        }
        return bestAlignment(foldedQuery: foldedQuery, text: textCharacters)?.score
    }

    /// `query` が `text` に部分列として現れるときの、一致した `text` の文字インデックス集合。
    /// 強調表示(ハイライト)用。`score(query:text:)` と全く同じ最適アライメントを再利用するため、
    /// 画面上の強調位置はスコアリングが実際に採用したマッチ位置と常に一致する。並び・スコアには
    /// 影響しない読み出し専用の補助(一致しなければ空)。
    public static func matchedIndices(query: String, text: String) -> [Int] {
        let queryCharacters = Array(query)
        let foldedQuery = caseFolded(queryCharacters)
        guard !foldedQuery.isEmpty else { return [] }

        let textCharacters = Array(text)
        if let filename = filenameAlignment(
            query: queryCharacters, foldedQuery: foldedQuery, text: textCharacters
        ) {
            return filename.indices
        }
        return bestAlignment(foldedQuery: foldedQuery, text: textCharacters)?.indices ?? []
    }

    /// ファイル名部分だけで一致が成立するときの最適アライメント。インデックスはパス全体の
    /// 座標へオフセット済み。入力が `/` を含む場合はパス全体で照合すべきなので常に nil。
    private static func filenameAlignment(
        query: [Character], foldedQuery: [Character], text: [Character]
    ) -> Alignment? {
        guard !query.contains("/") else { return nil }
        guard let filenameStart = filenameStartIndex(of: text) else { return nil }
        guard let alignment = bestAlignment(
            foldedQuery: foldedQuery, text: Array(text[filenameStart...])
        ) else { return nil }
        return Alignment(
            score: alignment.score, indices: alignment.indices.map { $0 + filenameStart }
        )
    }

    // MARK: - Private

    /// 最適アライメントの結果。スコアと、採用した `text` 側の一致位置集合(昇順)。
    private struct Alignment {
        let score: Int
        let indices: [Int]
    }

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

    /// 部分列としての対応付けのうち最良のもの(スコアと一致位置)。部分列でなければ nil。
    ///
    /// 貪欲に左から詰めると「後ろに出てくる連続一致」を取り逃すため、
    /// query × text の動的計画法で最良の対応付けを選ぶ。採用したアライメントの一致位置を
    /// バックポインタで復元して返すので、ハイライトはスコアリングと同じ位置を必ず指す。
    /// text 長に比例した事前の部分列判定で大半の候補を弾いてから DP に入る。
    private static func bestAlignment(foldedQuery: [Character], text: [Character]) -> Alignment? {
        // fold は 1 度だけ。部分列判定と DP のマッチング比較の双方でこの配列を使う。
        let folded = caseFolded(text)
        guard isSubsequence(query: foldedQuery, text: folded) else { return nil }

        // 単語境界(キャメルケース)判定は大小を見るため、畳み込み前の text を使う。
        let boundaries = (0 ..< text.count).map { isWordBoundary(text, at: $0) }
        let queryCount = foldedQuery.count
        let textCount = text.count

        // previous[j] = query の 1 つ前までを text[j] で終える形に対応付けた最良スコア。
        var previous = [Int?](repeating: nil, count: textCount)
        var current = [Int?](repeating: nil, count: textCount)
        // parent[q][j] = query[q] を text[j] に一致させたときの、直前の query 文字の一致位置。
        // 先頭 query 文字なら -1。バックトラックで採用アライメントを復元するために保持する。
        var parent = [[Int]](repeating: [Int](repeating: -1, count: textCount), count: queryCount)

        for queryIndex in 0 ..< queryCount {
            let queryCharacter = foldedQuery[queryIndex]
            // prefixMaximum[j] = previous[0...j] の最大値と、その値を与える位置(argmax)。
            // 非連続の対応付けを O(1) で引きつつ、どの位置から来たかを復元する。
            var prefixMaximumValue = [Int?](repeating: nil, count: textCount)
            var prefixMaximumArgument = [Int](repeating: -1, count: textCount)
            if queryIndex > 0 {
                var running: Int?
                var runningArgument = -1
                for index in 0 ..< textCount {
                    if let candidate = previous[index], running == nil || candidate > running! {
                        running = candidate
                        runningArgument = index
                    }
                    prefixMaximumValue[index] = running
                    prefixMaximumArgument[index] = runningArgument
                }
            }

            for textIndex in 0 ..< textCount {
                guard folded[textIndex] == queryCharacter else {
                    current[textIndex] = nil
                    continue
                }
                let characterScore = matchBase + (boundaries[textIndex] ? boundaryBonus : 0)

                guard queryIndex > 0 else {
                    current[textIndex] = characterScore
                    parent[queryIndex][textIndex] = -1
                    continue
                }
                var best: Int?
                var bestParent = -1
                // 間を空けて続ける場合。直前の一致は textIndex - 2 以前で終わっている。
                if textIndex >= 2, let gapped = prefixMaximumValue[textIndex - 2] {
                    best = gapped + characterScore
                    bestParent = prefixMaximumArgument[textIndex - 2]
                }
                // 直前の文字に続けて一致する場合。
                if textIndex >= 1, let consecutive = previous[textIndex - 1] {
                    let candidate = consecutive + characterScore + consecutiveBonus
                    if best == nil || candidate > best! {
                        best = candidate
                        bestParent = textIndex - 1
                    }
                }
                current[textIndex] = best
                parent[queryIndex][textIndex] = bestParent
            }
            swap(&previous, &current)
        }

        // 最終 query 行の最良位置を求め、そこから parent を辿ってアライメントを復元する。
        var bestScore: Int?
        var bestEnd = -1
        for index in 0 ..< textCount {
            if let candidate = previous[index], bestScore == nil || candidate > bestScore! {
                bestScore = candidate
                bestEnd = index
            }
        }
        guard let score = bestScore else { return nil }

        var indices: [Int] = []
        var queryIndex = queryCount - 1
        var textIndex = bestEnd
        while queryIndex >= 0, textIndex >= 0 {
            indices.append(textIndex)
            textIndex = parent[queryIndex][textIndex]
            queryIndex -= 1
        }
        indices.reverse()
        return Alignment(score: score, indices: indices)
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
}
