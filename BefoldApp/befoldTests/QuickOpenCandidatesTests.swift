@testable import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// git 索引はスタブを注入し、走査だけ実ファイルツリーで確かめる。
struct QuickOpenCandidatesTests {
    /// `trackedFileIndex(forFileAt:)` に渡された URL を記録し、collect が索引へ
    /// 「開いているファイル」を渡しているか(= ルートのディレクトリを渡す誤用でないか)を検証させる。
    private final class StubGitIndex: GitFileIndexing, @unchecked Sendable {
        let tracked: [URL]?
        private(set) var requestedURL: URL?

        init(tracked: [URL]?) {
            self.tracked = tracked
        }

        func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
            requestedURL = url
            return tracked.map { SuffixPathIndex(candidates: $0) }
        }
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    private func collect(
        root: URL,
        anchorFile: URL? = nil,
        tracked: [URL]?,
        recent: [URL] = [],
        bookmarks: [URL] = [],
        includingHiddenFiles: Bool = false,
        scanner: DirectoryFileScanner = DirectoryFileScanner()
    ) -> QuickOpenCandidateSet {
        QuickOpenCandidates.collect(
            root: root,
            anchorFile: anchorFile ?? root.appendingPathComponent("anchor.md"),
            gitIndex: StubGitIndex(tracked: tracked),
            scanner: scanner,
            recentURLs: recent,
            bookmarkedURLs: bookmarks,
            includingHiddenFiles: includingHiddenFiles
        )
    }

    @Test("git 索引にはルートのディレクトリではなく開いているファイルを渡す")
    func passesAnchorFileToGitIndex() {
        let stub = StubGitIndex(tracked: [url("/repo/a.md")])
        _ = QuickOpenCandidates.collect(
            root: url("/repo"),
            anchorFile: url("/repo/docs/x.md"),
            gitIndex: stub,
            scanner: DirectoryFileScanner(),
            recentURLs: [],
            bookmarkedURLs: [],
            includingHiddenFiles: false
        )

        #expect(stub.requestedURL == url("/repo/docs/x.md"))
        // ルートのディレクトリを渡す誤用(修正前の挙動)を検知する。
        #expect(stub.requestedURL != url("/repo"))
    }

    @Test("git 索引があれば追跡ファイルを候補にする")
    func usesTrackedFilesWhenAvailable() {
        let root = url("/repo")
        let set = collect(root: root, tracked: [url("/repo/src/a.swift"), url("/repo/b.md")])

        #expect(set.candidates.map(\.displayPath) == ["b.md", "src/a.swift"])
        #expect(set.isTruncated == false)
    }

    @Test("git 管理外ならディレクトリ走査の結果を使い、打ち切りを引き継ぐ")
    func fallsBackToDirectoryScan() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.md", contents: "")
        _ = try tmp.file(named: "b.md", contents: "")

        let set = collect(root: tmp.url, tracked: nil, scanner: DirectoryFileScanner(maximumCount: 1))

        #expect(set.candidates.map(\.displayPath) == ["a.md"])
        #expect(set.isTruncated)
    }

    @Test("履歴とブックマークを候補に混ぜる")
    func mergesRecentAndBookmarks() {
        let root = url("/repo")
        let set = collect(
            root: root,
            tracked: [url("/repo/tracked.md")],
            recent: [url("/repo/recent.md")],
            bookmarks: [url("/repo/marked.md")]
        )

        #expect(Set(set.candidates.map(\.displayPath)) == ["tracked.md", "recent.md", "marked.md"])
    }

    @Test("同一ファイルは normalizedPathKey で重複除去し履歴側を残す")
    func deduplicatesByNormalizedPathKey() {
        let root = url("/repo")
        let set = collect(
            root: root,
            tracked: [url("/repo/same.md")],
            recent: [url("/repo/same.md")],
            bookmarks: [url("/repo/same.md")]
        )

        #expect(set.candidates.count == 1)
        #expect(set.candidates.first?.origin == .recent)
    }

    @Test("displayPath は root からの相対、root 外は絶対パスになる")
    func buildsDisplayPaths() {
        let set = collect(
            root: url("/repo"),
            tracked: [url("/repo/src/a.swift")],
            recent: [url("/elsewhere/outside.md")]
        )

        let byPath = Dictionary(uniqueKeysWithValues: set.candidates.map { ($0.url, $0.displayPath) })
        #expect(byPath[url("/repo/src/a.swift")] == "src/a.swift")
        #expect(byPath[url("/elsewhere/outside.md")] == "/elsewhere/outside.md")
    }

    @Test("隠しファイルは設定に従って候補から外す")
    func honorsHiddenFilesSetting() {
        let root = url("/repo")
        let tracked = [url("/repo/visible.md"), url("/repo/.hidden.md"), url("/repo/.config/x.md")]

        let excluded = collect(root: root, tracked: tracked, includingHiddenFiles: false)
        #expect(excluded.candidates.map(\.displayPath) == ["visible.md"])

        let included = collect(root: root, tracked: tracked, includingHiddenFiles: true)
        #expect(included.candidates.count == 3)
    }

    @Test("空入力の一覧は履歴→ブックマークの順で上限まで返す")
    func initialCandidatesOrdering() {
        let root = url("/repo")
        let set = collect(
            root: root,
            tracked: [url("/repo/tracked.md")],
            recent: [url("/repo/r1.md"), url("/repo/r2.md")],
            bookmarks: [url("/repo/m1.md")]
        )

        #expect(set.initialCandidates(limit: 10).map(\.displayPath) == ["r1.md", "r2.md", "m1.md"])
        #expect(set.initialCandidates(limit: 2).map(\.displayPath) == ["r1.md", "r2.md"])
    }

    @Test("fuzzy 検索では履歴の加点が同点の候補を押し上げる")
    func recentGetsScoreBonus() {
        let root = url("/repo")
        let set = collect(
            root: root,
            tracked: [url("/repo/a/x.md")],
            recent: [url("/repo/b/x.md")]
        )

        // ファイル名が同じでスコアは同点。パス昇順なら a/x.md が先だが、履歴加点で逆転する。
        #expect(set.matches(query: "x", limit: 10).map(\.displayPath) == ["b/x.md", "a/x.md"])
    }

    @Test("fuzzy 検索は一致しない候補を落とし上限で打ち切る")
    func matchesFilterAndLimit() {
        let root = url("/repo")
        let set = collect(
            root: root,
            tracked: [url("/repo/alpha.md"), url("/repo/beta.md"), url("/repo/zzz.md")]
        )

        #expect(set.matches(query: "a", limit: 10).map(\.displayPath) == ["alpha.md", "beta.md"])
        #expect(set.matches(query: "a", limit: 1).map(\.displayPath) == ["alpha.md"])
    }
}
