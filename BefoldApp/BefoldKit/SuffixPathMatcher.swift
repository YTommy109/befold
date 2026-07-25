import Foundation

/// 書かれたパスを候補ファイル群へ「/ 区切りの構成要素単位」でサフィックス照合し、
/// 開いているファイル(baseURL)からのディレクトリツリー距離が最小の 1 件を返す。
/// 曖昧さは 距離最小 → up 段数最小 → path 昇順 のタイブレークで決定論的に解消する。
public enum SuffixPathMatcher {
    /// 単発照合。候補の前処理を毎回やり直すため、同じ候補集合へ繰り返し照合する場合は
    /// `SuffixPathIndex` を 1 度だけ構築して使い回すこと。
    public static func bestMatch(writtenPath: String, candidates: [URL], baseURL: URL) -> URL? {
        SuffixPathIndex(candidates: candidates).bestMatch(writtenPath: writtenPath, baseURL: baseURL)
    }

    /// "/", ".", "..", 空要素を除いたパス構成要素。
    static func meaningfulComponents(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." && !$0.isEmpty }
    }

    /// ルート "/" を除いた URL の構成要素。
    static func components(of url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    }

    /// haystack の末尾 needle.count 個が needle と一致するか。
    static func hasComponentSuffix(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return Array(haystack.suffix(needle.count)) == needle
    }

    /// 共通接頭辞を除いた (合計距離, 上がる段数)。
    static func distance(_ first: [String], _ second: [String]) -> (total: Int, up: Int) {
        var index = 0
        while index < first.count, index < second.count, first[index] == second[index] {
            index += 1
        }
        let upSteps = first.count - index
        let downSteps = second.count - index
        return (upSteps + downSteps, upSteps)
    }
}

/// 候補ファイル群を 1 度だけ前処理して繰り返しのサフィックス照合に備える索引。
///
/// 候補ごとの構成要素は `standardizedFileURL` を経由する = ファイルシステムに触る正規化であり、
/// 単なる文字列操作ではない。照合のたびに、しかも比較子の内側で計算すると
/// 参照数 × 候補数 のオーダーで正規化が走り、大きなリポジトリでは描画がフリーズする。
/// 前処理を構築時へ追い出し、さらに最終構成要素をキーに引くことで、
/// 1 参照あたりの走査を「同名ファイルの数」まで畳む
/// (サフィックス一致は必ず最終構成要素の一致を含むため、この索引で候補を落とすことはない)。
public struct SuffixPathIndex: Sendable {
    private struct Candidate: Sendable {
        /// 呼び出し元へ返す元の URL(正規化前)。
        let url: URL
        let components: [String]
        /// 距離計算に使う親ディレクトリの構成要素。`components` の末尾を落とすのではなく
        /// `deletingLastPathComponent()` を正規化して求める(末尾がシンボリックリンクの場合に
        /// 両者は一致しないため、既存の距離計算と同じ値を保つ)。
        let directoryComponents: [String]
        /// タイブレーク用の正規化済みパス。
        let standardizedPath: String
    }

    private let candidatesByLastComponent: [String: [Candidate]]

    public init(candidates: [URL]) {
        var grouped: [String: [Candidate]] = [:]
        for url in candidates {
            let standardized = url.standardizedFileURL
            let components = standardized.pathComponents.filter { $0 != "/" }
            // 構成要素を持たない候補(ルート)はどんな needle にも一致しないため落とす。
            guard let lastComponent = components.last else { continue }
            grouped[lastComponent, default: []].append(Candidate(
                url: url,
                components: components,
                directoryComponents: SuffixPathMatcher.components(of: url.deletingLastPathComponent()),
                standardizedPath: standardized.path
            ))
        }
        candidatesByLastComponent = grouped
    }

    /// 距離最小 → up 段数最小 → 正規化パス昇順 で最良の 1 件を返す。
    public func bestMatch(writtenPath: String, baseURL: URL) -> URL? {
        let needle = SuffixPathMatcher.meaningfulComponents(writtenPath)
        guard let lastNeedle = needle.last,
              let bucket = candidatesByLastComponent[lastNeedle]
        else { return nil }
        let baseDirectory = SuffixPathMatcher.components(of: baseURL.deletingLastPathComponent())

        var best: (candidate: Candidate, distance: (total: Int, up: Int))?
        for candidate in bucket {
            guard SuffixPathMatcher.hasComponentSuffix(candidate.components, needle) else { continue }
            let distance = SuffixPathMatcher.distance(baseDirectory, candidate.directoryComponents)
            // 同点では先に現れた候補を残し、min(by:) と同じ結果に揃える。
            guard let current = best else {
                best = (candidate, distance)
                continue
            }
            if isBetter(candidate, distance, than: current.candidate, current.distance) {
                best = (candidate, distance)
            }
        }
        return best?.candidate.url
    }

    private func isBetter(
        _ lhs: Candidate, _ lhsDistance: (total: Int, up: Int),
        than rhs: Candidate, _ rhsDistance: (total: Int, up: Int)
    ) -> Bool {
        if lhsDistance.total != rhsDistance.total { return lhsDistance.total < rhsDistance.total }
        if lhsDistance.up != rhsDistance.up { return lhsDistance.up < rhsDistance.up }
        return lhs.standardizedPath < rhs.standardizedPath
    }
}
