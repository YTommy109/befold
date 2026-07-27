@testable import BefoldKit
import Foundation
import Testing

/// スコアの絶対値は検証しない(チューニングのたびに壊れるため)。
/// 検証対象は「どちらが上位に来るか」という順序と、一致/不一致の判定に限る。
struct FuzzyMatcherTests {
    /// score() の相対値が期待する並び(スコア降順・同点はテキスト昇順)になるかを検証する
    /// ためのヘルパー。順位付けの実体は本番では QuickOpenCandidateSet.matches が持つため、
    /// ここではテスト内で同じ規則を組み立てて score() の出力だけを確かめる。
    private func rankedTexts(_ query: String, _ texts: [String], limit: Int? = nil) -> [String] {
        var scored: [(text: String, score: Int)] = []
        for text in texts {
            guard let score = FuzzyMatcher.score(query: query, text: text) else { continue }
            scored.append((text, score))
        }
        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.text < rhs.text : lhs.score > rhs.score
        }
        let ordered = scored.map(\.text)
        guard let limit else { return ordered }
        return Array(ordered.prefix(limit))
    }

    @Test("部分列でない入力は一致しない")
    func rejectsNonSubsequence() {
        #expect(FuzzyMatcher.score(query: "xyz", text: "abc.swift") == nil)
    }

    @Test("順序が違う部分列は一致しない")
    func rejectsOutOfOrderSubsequence() {
        #expect(FuzzyMatcher.score(query: "cb", text: "abc") == nil)
    }

    @Test("大文字小文字を無視して一致する")
    func matchesCaseInsensitively() {
        #expect(FuzzyMatcher.score(query: "VW", text: "ViewerWebView.swift") != nil)
        #expect(FuzzyMatcher.score(query: "vw", text: "ViewerWebView.swift") != nil)
    }

    @Test("連続一致は飛び飛びの一致より上位に来る")
    func consecutiveBeatsScattered() {
        #expect(rankedTexts("abc", ["axbxcx.txt", "abcxxx.txt"]).first == "abcxxx.txt")
    }

    @Test("単語境界での一致は語中の一致より上位に来る")
    func wordBoundaryBeatsMidWord() {
        #expect(rankedTexts("qo", ["aqaoa.swift", "quick_open.swift"]).first == "quick_open.swift")
    }

    @Test("キャメルケース境界での一致は語中の一致より上位に来る")
    func camelCaseBoundaryBeatsMidWord() {
        #expect(rankedTexts("vw", ["avawa.swift", "ViewerWebView.swift"]).first == "ViewerWebView.swift")
    }

    @Test("ファイル名での一致はディレクトリ名での一致より上位に来る")
    func filenameBeatsDirectory() {
        #expect(rankedTexts("util", ["util/main.swift", "src/util.swift"]).first == "src/util.swift")
    }

    @Test("入力に / を含む場合はパス全体に照合する")
    func slashQueryMatchesWholePath() {
        #expect(FuzzyMatcher.score(query: "src/util", text: "src/util.swift") != nil)
        // ファイル名だけでは "src/" を満たせないため、パス全体への照合が効いている
        #expect(FuzzyMatcher.score(query: "src/util", text: "other/util.swift") == nil)
    }

    @Test("同点はテキスト昇順で決定論的に並ぶ")
    func deterministicTieBreak() {
        // ファイル名が同一なのでスコアも同一。並びは text の昇順で確定する。
        let texts = ["z/ab.txt", "a/ab.txt", "m/ab.txt"]
        #expect(rankedTexts("ab", texts) == ["a/ab.txt", "m/ab.txt", "z/ab.txt"])
    }

    @Test("一致しない候補は結果から落ちる")
    func dropsNonMatching() {
        #expect(rankedTexts("ab", ["ab.txt", "zzz.txt"]) == ["ab.txt"])
    }

    @Test("limit で件数を打ち切る")
    func appliesLimit() {
        let texts = ["a/ab.txt", "m/ab.txt", "z/ab.txt"]
        #expect(rankedTexts("ab", texts, limit: 2) == ["a/ab.txt", "m/ab.txt"])
    }

    @Test("空の入力は全件を一致として返す")
    func emptyQueryMatchesEverything() {
        #expect(rankedTexts("", ["b.txt", "a.txt"]) == ["a.txt", "b.txt"])
    }

    // MARK: - matchedIndices(強調位置)

    @Test("連続一致の位置を返す")
    func matchedIndicesConsecutive() {
        #expect(FuzzyMatcher.matchedIndices(query: "abc", text: "abcxxx") == [0, 1, 2])
    }

    @Test("飛び飛びの一致でもそれぞれの位置を返す")
    func matchedIndicesScattered() {
        #expect(FuzzyMatcher.matchedIndices(query: "abc", text: "axbxcx") == [0, 2, 4])
    }

    @Test("単語境界の一致位置を返す(大小無視)")
    func matchedIndicesWordBoundary() {
        // quick_open.swift の q(0) と open の o(6)
        #expect(FuzzyMatcher.matchedIndices(query: "QO", text: "quick_open.swift") == [0, 6])
    }

    @Test("/ を含まない入力はファイル名部分の位置(オフセット付き)を返す")
    func matchedIndicesUsesFilenameOffset() {
        // "util" はディレクトリ名にもあるが、ファイル名 util.swift 側で一致する
        let indices = FuzzyMatcher.matchedIndices(query: "util", text: "src/util.swift")
        #expect(indices == [4, 5, 6, 7]) // "util" of util.swift(src/ の後)
    }

    @Test("/ を含む入力はパス全体で一致位置を返す")
    func matchedIndicesWholePathForSlashQuery() {
        #expect(FuzzyMatcher.matchedIndices(query: "s/u", text: "src/util.swift") == [0, 3, 4])
    }

    @Test("一致しなければ空を返す")
    func matchedIndicesEmptyWhenNoMatch() {
        #expect(FuzzyMatcher.matchedIndices(query: "xyz", text: "abc.swift").isEmpty)
    }

    @Test("スコアリングが採用した連続一致と同じ位置を強調する")
    func matchedIndicesFollowsScoringAlignment() {
        // "IsolatedDefaults.swift" には末尾 "Isolated" の d と、
        // 単語境界の "Default" の両方に d がある。貪欲だと前者の d(7) を拾って
        // 飛び飛びになるが、スコアリングは連続する "Default"(8..14) を採用する。
        // ハイライトもそのアライメントに一致しなければならない。
        let indices = FuzzyMatcher.matchedIndices(query: "default", text: "IsolatedDefaults.swift")
        #expect(indices == [8, 9, 10, 11, 12, 13, 14])
    }
}
