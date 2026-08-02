@testable import BefoldKit
import Foundation
import Testing

private struct FakeGitIndex: GitFileIndexing {
    let files: [URL]?
    func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
        files.map(SuffixPathIndex.init(candidates:))
    }
}

/// 追跡ファイル索引の取得回数を数える索引。バッチ解決が git を 1 度しか引かないことの検証に使う。
private final class CountingGitIndex: GitFileIndexing, @unchecked Sendable {
    private let files: [URL]?
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }; return _callCount
    }

    init(files: [URL]?) {
        self.files = files
    }

    func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return files.map(SuffixPathIndex.init(candidates:))
    }
}

struct TrackedPathResolverTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    /// 指定した URL だけが存在するファイルとして解決される InMemoryFileReader を組み立てる。
    /// 中身は判定に使わないため空文字で埋める。
    private func fileReader(existing: [URL]) -> InMemoryFileReader {
        InMemoryFileReader(files: Dictionary(uniqueKeysWithValues: existing.map { ($0.path, "") }))
    }

    @Test("相対で実在すればそのまま解決する(git を見ない)")
    func resolvesExistingRelative() {
        let base = url("/repo/docs/guide.md")
        let target = url("/repo/docs/img.png")
        let sut = TrackedPathResolver(
            fileReader: fileReader(existing: [target]),
            gitIndex: FakeGitIndex(files: nil)
        )
        #expect(sut.resolve(href: "img.png", baseURL: base) == .resolved(target))
    }

    @Test("相対で実在しなければ git 追跡ファイルへサフィックス一致で解決する")
    func resolvesViaGitSuffix() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let sut = TrackedPathResolver(
            fileReader: fileReader(existing: [tracked]),
            gitIndex: FakeGitIndex(files: [tracked])
        )
        #expect(sut.resolve(href: "utils.swift", baseURL: base) == .resolved(tracked))
    }

    /// git の索引は worktree の実態と一致しない。worktree から削除して index に残っている
    /// ファイルや submodule の gitlink(実体はディレクトリ)も列挙されるため、
    /// 一致しただけでリンク化すると「クリックしても開けないリンク」になる。
    @Test("git が追跡していても worktree に実在しなければ unresolved")
    func unresolvedWhenTrackedFileIsMissingFromWorktree() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let sut = TrackedPathResolver(
            fileReader: fileReader(existing: []),
            gitIndex: FakeGitIndex(files: [tracked])
        )
        #expect(sut.resolve(href: "utils.swift", baseURL: base) == .unresolved)
    }

    @Test("git 管理外かつ相対で実在しなければ unresolved")
    func unresolvedWithoutGit() {
        let sut = TrackedPathResolver(
            fileReader: fileReader(existing: []),
            gitIndex: FakeGitIndex(files: nil)
        )
        #expect(sut.resolve(href: "utils.swift", baseURL: url("/repo/x.md")) == .unresolved)
    }

    @Test("外部 URL は external、アンカー/空は ignored")
    func classifiesExternalAndIgnored() throws {
        let sut = TrackedPathResolver(
            fileReader: fileReader(existing: []),
            gitIndex: FakeGitIndex(files: nil)
        )
        let base = url("/repo/x.md")
        #expect(try sut.resolve(href: "https://example.com", baseURL: base)
            == .external(#require(URL(string: "https://example.com"))))
        #expect(sut.resolve(href: "#section", baseURL: base) == .ignored)
    }

    @Test("resolveAll は単発 resolve と同じ結果を返す")
    func resolveAllMatchesSingleResolve() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let existing = url("/repo/docs/img.png")
        let hrefs = ["utils.swift", "img.png", "nope.swift", "https://example.com", "#section"]
        let makeSUT = {
            TrackedPathResolver(
                fileReader: fileReader(existing: [existing, tracked]),
                gitIndex: CountingGitIndex(files: [tracked])
            )
        }

        let batch = makeSUT().resolveAll(hrefs: hrefs, baseURL: base)

        let single = makeSUT()
        for href in hrefs {
            #expect(batch[href] == single.resolve(href: href, baseURL: base), "href=\(href)")
        }
    }

    @Test("resolveAll は git 追跡ファイルの取得をバッチで 1 度に抑える")
    func resolveAllFetchesTrackedFilesOnce() {
        let index = CountingGitIndex(files: [url("/repo/src/utils.swift")])
        let sut = TrackedPathResolver(fileReader: fileReader(existing: []), gitIndex: index)

        _ = sut.resolveAll(
            hrefs: ["utils.swift", "other.swift", "third.swift"],
            baseURL: url("/repo/docs/guide.md")
        )

        #expect(index.callCount == 1)
    }

    @Test("相対解決だけで片付くバッチは git を一切引かない")
    func resolveAllSkipsGitWhenAllRelativePathsExist() {
        let existing = url("/repo/docs/img.png")
        let index = CountingGitIndex(files: [url("/repo/src/utils.swift")])
        let sut = TrackedPathResolver(
            fileReader: fileReader(existing: [existing]), gitIndex: index
        )

        _ = sut.resolveAll(hrefs: ["img.png", "https://example.com"], baseURL: url("/repo/docs/guide.md"))

        #expect(index.callCount == 0)
    }

    @Test("行番号サフィックス付きでも解決できる")
    func resolvesWithLineSuffix() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let sut = TrackedPathResolver(
            fileReader: fileReader(existing: [tracked]),
            gitIndex: FakeGitIndex(files: [tracked])
        )
        #expect(sut.resolve(href: "utils.swift:42", baseURL: base) == .resolved(tracked))
    }
}
