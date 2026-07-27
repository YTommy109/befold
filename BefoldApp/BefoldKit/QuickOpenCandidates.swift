import Foundation

/// Quick Open の候補 1 件。
public struct QuickOpenCandidate: Equatable, Sendable {
    /// どこから来た候補か。表示の出し分けと fuzzy 検索時の加点に使う。
    public enum Origin: Equatable, Sendable {
        case recent
        case bookmark
        /// git 追跡ファイル索引、またはディレクトリ走査。
        case indexed
    }

    public let url: URL
    /// リストに出す文字列。root 配下なら相対パス、root の外なら絶対パス。
    /// fuzzy 検索の照合対象もこの文字列で、表示と一致の対象をずらさない。
    public let displayPath: String
    public let origin: Origin

    public init(url: URL, displayPath: String, origin: Origin) {
        self.url = url
        self.displayPath = displayPath
        self.origin = origin
    }
}

/// 重複除去済みの候補集合。入力に応じた絞り込みはここが受け持つ。
public struct QuickOpenCandidateSet: Equatable, Sendable {
    /// 履歴 → ブックマーク → 索引/走査 の順に並んだ候補。
    public let candidates: [QuickOpenCandidate]
    /// 走査が上限で打ち切られたか。リスト末尾にその旨を出すために使う。
    public let isTruncated: Bool

    public init(candidates: [QuickOpenCandidate], isTruncated: Bool) {
        self.candidates = candidates
        self.isTruncated = isTruncated
    }

    /// 空入力時に出す一覧。履歴を上に、続けてブックマークを並べる。
    public func initialCandidates(limit: Int = 20) -> [QuickOpenCandidate] {
        Array(candidates.filter { $0.origin != .indexed }.prefix(limit))
    }

    /// 入力で候補を絞り込み、スコア降順に並べて返す。
    /// 同点は正規化パス昇順で確定させ、同じ入力に常に同じ並びを返す。
    public func matches(query: String, limit: Int = 50) -> [QuickOpenCandidate] {
        var scored: [(candidate: QuickOpenCandidate, score: Int)] = []
        for candidate in candidates {
            guard let score = FuzzyMatcher.score(query: query, text: candidate.displayPath) else { continue }
            scored.append((candidate, score + Self.originBonus(candidate.origin)))
        }
        scored.sort { lhs, rhs in
            lhs.score == rhs.score
                ? lhs.candidate.url.normalizedPathKey < rhs.candidate.url.normalizedPathKey
                : lhs.score > rhs.score
        }
        return scored.prefix(limit).map(\.candidate)
    }

    /// 一度開いた/印を付けたファイルは次も選ばれやすい、という前提の加点。
    /// 一致の質(連続一致や単語境界)を覆すほどではない大きさに抑え、
    /// 打った入力によく合う候補が履歴に押しのけられないようにしている。
    private static func originBonus(_ origin: QuickOpenCandidate.Origin) -> Int {
        switch origin {
        case .recent: 30
        case .bookmark: 20
        case .indexed: 0
        }
    }
}

/// git 追跡ファイル索引・ディレクトリ走査・履歴・ブックマークを 1 つの候補集合にまとめる。
public enum QuickOpenCandidates {
    /// - Parameters:
    ///   - root: 表示パスの基準であり、git 管理外のときの走査の起点。
    ///   - anchorFile: 追跡ファイル索引を引く起点となる「開いているファイル」。`gitIndex` は
    ///     ファイルの所属リポジトリを解決するため、ここには走査対象のルート(ディレクトリ)ではなく
    ///     ファイル URL を渡す。ルートを渡すと索引がルートの親を起点に解決し、常に取りこぼす。
    ///   - gitIndex: 追跡ファイル索引。nil を返す(= git 管理外)なら `scanner` に切り替える。
    ///   - includingHiddenFiles: 隠しファイルを候補に含めるか。独自設定を持たず、
    ///     呼び出し元(`HiddenFilesPreference`)の値をそのまま渡す。
    public static func collect(
        root: URL,
        anchorFile: URL,
        gitIndex: any GitFileIndexing,
        scanner: DirectoryFileScanner,
        recentURLs: [URL],
        bookmarkedURLs: [URL],
        includingHiddenFiles: Bool
    ) -> QuickOpenCandidateSet {
        let indexed: [URL]
        let isTruncated: Bool
        if let trackedIndex = gitIndex.trackedFileIndex(forFileAt: anchorFile) {
            indexed = trackedIndex.allCandidates
            isTruncated = false
        } else {
            let scan = scanner.scan(root: root, includingHiddenFiles: includingHiddenFiles)
            indexed = scan.files
            isTruncated = scan.isTruncated
        }

        // 追跡ファイル索引は隠しファイル設定を通っていないため、ここで揃える。
        // 走査側は既に設定どおりだが、同じ条件を二度かけても結果は変わらない。
        let visibleIndexed = includingHiddenFiles
            ? indexed
            : indexed.filter { !isHidden($0, below: root) }

        // ブックマークは保存順を持たないため、表示パス昇順に固定して並びをぶれさせない。
        let sortedBookmarks = bookmarkedURLs.sorted {
            displayPath(of: $0, root: root) < displayPath(of: $1, root: root)
        }

        var seen: Set<String> = []
        var candidates: [QuickOpenCandidate] = []
        // 先に入れた出自が残る。履歴を先頭に置くことで、索引にも載っている
        // ファイルが履歴としての加点を失わないようにしている。
        for (urls, origin) in [
            (recentURLs, QuickOpenCandidate.Origin.recent),
            (sortedBookmarks, .bookmark),
            (visibleIndexed, .indexed),
        ] {
            for url in urls where seen.insert(url.normalizedPathKey).inserted {
                candidates.append(QuickOpenCandidate(
                    url: url, displayPath: displayPath(of: url, root: root), origin: origin
                ))
            }
        }
        return QuickOpenCandidateSet(candidates: candidates, isTruncated: isTruncated)
    }

    // MARK: - Private

    private static func displayPath(of url: URL, root: URL) -> String {
        PathRelativizer.relativePath(of: url, relativeTo: root)
    }

    /// root からの相対部分に、ドット始まりの構成要素が 1 つでもあるか。
    /// root 自体がドット始まりのディレクトリでも(例: `~/.config` を開いた場合)
    /// 配下が丸ごと隠し扱いにならないよう、判定は相対部分だけを見る。
    private static func isHidden(_ url: URL, below root: URL) -> Bool {
        let relative = PathRelativizer.relativePath(of: url, relativeTo: root)
        return relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }
}
