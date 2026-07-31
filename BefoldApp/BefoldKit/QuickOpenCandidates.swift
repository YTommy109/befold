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
    /// 同点タイブレーク用に事前計算した正規化パスキー。`normalizedPathKey` は
    /// `resolvingSymlinksInPath()`(構成要素ぶんの FS I/O)を伴うため、キーストロークごとに
    /// 走る `matches()` の比較子内では計算せず、生成時に一度だけ求めた値をここで持ち回る。
    public let sortKey: String

    public init(url: URL, displayPath: String, origin: Origin, sortKey: String? = nil) {
        self.url = url
        self.displayPath = displayPath
        self.origin = origin
        // 呼び出し元が重複除去などで既に計算済みならその値を使い、二重計算を避ける。
        self.sortKey = sortKey ?? url.normalizedPathKey
    }
}

/// 重複除去済みの候補集合。入力に応じた絞り込みはここが受け持つ。
public struct QuickOpenCandidateSet: Equatable, Sendable {
    /// 索引に載っている履歴(recency 順) → 索引/走査(ブックマーク印つき) の順に並んだ候補。
    /// 履歴・ブックマークは候補ソースにはせず、索引に載っているファイルへ origin を付けるだけ。
    public let candidates: [QuickOpenCandidate]
    /// 走査が上限で打ち切られたか。リスト末尾にその旨を出すために使う。
    public let isTruncated: Bool

    public init(candidates: [QuickOpenCandidate], isTruncated: Bool) {
        self.candidates = candidates
        self.isTruncated = isTruncated
    }

    /// 空入力時に出す一覧。索引に載っている履歴(recent)のみを新しい順で返す。
    /// ブックマーク専用・索引外の履歴は出さず、羅列ノイズを避ける。
    /// 上限は呼び出し元(`QuickOpenModel`)が単一情報源として持つため、既定値は設けない。
    public func initialCandidates(limit: Int) -> [QuickOpenCandidate] {
        Array(candidates.filter { $0.origin == .recent }.prefix(limit))
    }

    /// 入力で候補を絞り込み、スコア降順に並べて返す。
    /// 同点は正規化パス昇順で確定させ、同じ入力に常に同じ並びを返す。
    public func matches(query: String, limit: Int) -> [QuickOpenCandidate] {
        candidates
            .compactMap { candidate -> (candidate: QuickOpenCandidate, score: Int)? in
                guard let score = FuzzyMatcher.score(query: query, text: candidate.displayPath) else { return nil }
                return (candidate, score + Self.originBonus(candidate.origin))
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.candidate.sortKey < rhs.candidate.sortKey
                    : lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.candidate)
    }

    /// 一度開いた/印を付けたファイルは次も選ばれやすい、という前提の加点。
    /// 値はファイル名一致の加点(`filenameBonus` = 1000)より桁違いに小さく、複数文字の
    /// 一致で積み上がる基礎点・連続点にもすぐ埋もれるため、実質的にはスコアが拮抗した
    /// 候補どうしの並びを履歴・ブックマーク優先で決めるだけに働く。
    /// (単一文字の連続点+境界点=27 は上回るので、ごく短い入力では履歴が前に出うる。)
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

        // 候補ソースは索引/走査由来のファイルだけにする。履歴・ブックマークは候補として
        // 注入せず、索引に載っているファイルへ origin を付与するだけにする(専用エントリの
        // 羅列を避ける)。origin の優先度は recent > bookmark > indexed。
        let bookmarkKeys = Set(bookmarkedURLs.map(\.normalizedPathKey))

        // 索引を正規化パスキーで重複除去しつつ索引順を保つ。key は重複除去・同点タイブレーク・
        // membership 判定を兼ねるため、ここで一度だけ計算して持ち回る(比較子内の FS I/O をなくす)。
        var indexedByKey: [String: URL] = [:]
        var indexedOrder: [String] = []
        for url in visibleIndexed where indexedByKey[url.normalizedPathKey] == nil {
            let key = url.normalizedPathKey
            indexedByKey[key] = url
            indexedOrder.append(key)
        }

        var seen: Set<String> = []
        // 履歴かつ索引にあるファイルを recency 順で先頭に置く。空入力時の一覧
        // (initialCandidates)がこの並びをそのまま使うため、履歴の新しい順を保つ。
        var recentCandidates: [QuickOpenCandidate] = []
        for url in recentURLs {
            let key = url.normalizedPathKey
            guard let indexedURL = indexedByKey[key], seen.insert(key).inserted else { continue }
            recentCandidates.append(QuickOpenCandidate(
                url: indexedURL, displayPath: displayPath(of: indexedURL, root: root), origin: .recent, sortKey: key
            ))
        }

        // 残りの索引ファイルを索引順で。ブックマークに載っていれば bookmark を付ける。
        var otherCandidates: [QuickOpenCandidate] = []
        for key in indexedOrder {
            guard seen.insert(key).inserted, let url = indexedByKey[key] else { continue }
            let origin: QuickOpenCandidate.Origin = bookmarkKeys.contains(key) ? .bookmark : .indexed
            otherCandidates.append(QuickOpenCandidate(
                url: url, displayPath: displayPath(of: url, root: root), origin: origin, sortKey: key
            ))
        }

        return QuickOpenCandidateSet(candidates: recentCandidates + otherCandidates, isTruncated: isTruncated)
    }

    // MARK: - Private

    private static func displayPath(of url: URL, root: URL) -> String {
        PathRelativizer.relativePath(of: url, relativeTo: root)
    }

    /// root からの相対部分に、ドット始まりの構成要素が 1 つでもあるか。
    /// 判定の実体は `HiddenFileRule` に集約し、走査・索引・パスモードで同じ意味に揃える。
    private static func isHidden(_ url: URL, below root: URL) -> Bool {
        HiddenFileRule.containsHiddenComponent(
            inRelativePath: PathRelativizer.relativePath(of: url, relativeTo: root)
        )
    }
}
