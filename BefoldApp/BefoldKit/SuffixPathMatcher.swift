import Foundation

/// 書かれたパスを候補ファイル群へ「/ 区切りの構成要素単位」でサフィックス照合し、
/// 開いているファイル(baseURL)からのディレクトリツリー距離が最小の 1 件を返す。
/// 曖昧さは 距離最小 → up 段数最小 → path 昇順 のタイブレークで決定論的に解消する。
public enum SuffixPathMatcher {
    public static func bestMatch(writtenPath: String, candidates: [URL], baseURL: URL) -> URL? {
        let needle = meaningfulComponents(writtenPath)
        guard !needle.isEmpty else { return nil }
        let baseDir = components(of: baseURL.deletingLastPathComponent())

        let matches = candidates.filter { hasComponentSuffix(components(of: $0), needle) }
        guard !matches.isEmpty else { return nil }

        return matches.min { lhs, rhs in
            let lhsDistance = distance(baseDir, components(of: lhs.deletingLastPathComponent()))
            let rhsDistance = distance(baseDir, components(of: rhs.deletingLastPathComponent()))
            if lhsDistance.total != rhsDistance.total { return lhsDistance.total < rhsDistance.total }
            if lhsDistance.up != rhsDistance.up { return lhsDistance.up < rhsDistance.up }
            return lhs.standardizedFileURL.path < rhs.standardizedFileURL.path
        }
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
