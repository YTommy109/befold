@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// `warm` は別スレッドから `trackedFiles(at:)` を呼ぶため、このフェイクへの
/// アクセスはロックで直列化して race を避ける。
private final class FakeRepository: GitRepositoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _stubRoot: URL?
    private var _fingerprint: Date?
    private var _files: [URL]
    private var _trackedCallCount = 0

    var stubRoot: URL? {
        get { lock.lock(); defer { lock.unlock() }; return _stubRoot }
        set { lock.lock(); defer { lock.unlock() }; _stubRoot = newValue }
    }

    var fingerprint: Date? {
        get { lock.lock(); defer { lock.unlock() }; return _fingerprint }
        set { lock.lock(); defer { lock.unlock() }; _fingerprint = newValue }
    }

    var files: [URL] {
        get { lock.lock(); defer { lock.unlock() }; return _files }
        set { lock.lock(); defer { lock.unlock() }; _files = newValue }
    }

    var trackedCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _trackedCallCount
    }

    init(root: URL?, fingerprint: Date?, files: [URL]) {
        _stubRoot = root
        _fingerprint = fingerprint
        _files = files
    }

    func root(forFileAt url: URL) -> URL? {
        stubRoot
    }

    func trackedFiles(at root: URL) -> [URL] {
        lock.lock()
        _trackedCallCount += 1
        let result = _files
        lock.unlock()
        return result
    }

    func indexFingerprint(at root: URL) -> Date? {
        fingerprint
    }
}

/// ファイルの置かれたディレクトリをそのままリポジトリルートとみなす、複数リポジトリ用のフェイク。
/// LRU の追い出しを検証するために、ルートごとの列挙回数を数える。
private final class MultiRepoFake: GitRepositoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var callCountByRoot: [String: Int] = [:]

    func trackedCallCount(for root: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return callCountByRoot[root.path] ?? 0
    }

    func root(forFileAt url: URL) -> URL? {
        url.deletingLastPathComponent()
    }

    func trackedFiles(at root: URL) -> [URL] {
        lock.lock()
        callCountByRoot[root.path, default: 0] += 1
        lock.unlock()
        return [root.appendingPathComponent("a.swift")]
    }

    func indexFingerprint(at root: URL) -> Date? {
        Date(timeIntervalSince1970: 1)
    }
}

struct GitCommandFileIndexTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test("追跡ファイルを返す")
    func returnsTrackedFiles() {
        let repo = FakeRepository(
            root: url("/repo"),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)
        #expect(sut.trackedFiles(forFileAt: url("/repo/docs/x.md")) == [url("/repo/a.swift")])
    }

    @Test("git 管理外は nil")
    func returnsNilOutsideRepo() {
        let repo = FakeRepository(root: nil, fingerprint: nil, files: [])
        #expect(GitCommandFileIndex(repository: repo).trackedFiles(forFileAt: url("/x/y.md")) == nil)
    }

    @Test("同一 fingerprint では再列挙しない(キャッシュ命中)")
    func cachesWhileFingerprintUnchanged() {
        let repo = FakeRepository(
            root: url("/repo"),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)
        _ = sut.trackedFiles(forFileAt: url("/repo/docs/x.md"))
        _ = sut.trackedFiles(forFileAt: url("/repo/docs/y.md"))
        #expect(repo.trackedCallCount == 1)
    }

    @Test("fingerprint が変われば再列挙する(無効化)")
    func refetchesWhenFingerprintChanges() {
        let repo = FakeRepository(
            root: url("/repo"),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)
        _ = sut.trackedFiles(forFileAt: url("/repo/docs/x.md"))
        repo.fingerprint = Date(timeIntervalSince1970: 2) // 外部の checkout / commit 相当
        repo.files = [url("/repo/a.swift"), url("/repo/b.swift")]
        let after = sut.trackedFiles(forFileAt: url("/repo/docs/x.md"))
        #expect(repo.trackedCallCount == 2)
        #expect(after == [url("/repo/a.swift"), url("/repo/b.swift")])
    }

    /// この索引はアプリ寿命で生きるため、上限が無いと開いたことのある全リポジトリの
    /// 追跡ファイル一覧を抱え続ける。上限超過分が捨てられることを固定する。
    @Test("保持するリポジトリ数には上限があり、古いものから捨てられる")
    func evictsLeastRecentlyUsedRoots() {
        let repo = MultiRepoFake()
        let sut = GitCommandFileIndex(repository: repo)
        let limit = GitCommandFileIndex.maxCachedRoots
        let roots = (1 ... limit + 1).map { url("/repo\($0)") }

        // 上限ちょうどまで埋める。
        for root in roots.prefix(limit) {
            _ = sut.trackedFiles(forFileAt: root.appendingPathComponent("x.md"))
        }
        // どれも再列挙されない(全部キャッシュに載っている)。
        for root in roots.prefix(limit) {
            _ = sut.trackedFiles(forFileAt: root.appendingPathComponent("x.md"))
            #expect(repo.trackedCallCount(for: root) == 1)
        }

        // 上限を 1 つ超えると、最も古い roots[0] が押し出される。
        _ = sut.trackedFiles(forFileAt: roots[limit].appendingPathComponent("x.md"))

        _ = sut.trackedFiles(forFileAt: roots[0].appendingPathComponent("x.md"))
        #expect(repo.trackedCallCount(for: roots[0]) == 2, "追い出されたはずのルートが再列挙されていない")
        _ = sut.trackedFiles(forFileAt: roots[limit].appendingPathComponent("x.md"))
        #expect(repo.trackedCallCount(for: roots[limit]) == 1, "直近のルートまで捨てている")
    }

    @Test("warm はバックグラウンドでキャッシュを温める", testTimeLimit())
    func warmPopulatesCacheInBackground() async {
        let repo = FakeRepository(
            root: url("/repo"),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)

        sut.warm(forFileAt: url("/repo/docs/x.md"))

        // 固定 sleep ではなく、background の trackedFiles(at:) 呼び出しが
        // 反映されるまでポーリングで待つ。
        await waitUntil { repo.trackedCallCount == 1 }
        #expect(repo.trackedCallCount == 1)

        // warm で温めたキャッシュにより、同期呼び出しは再列挙せず命中する。
        _ = sut.trackedFiles(forFileAt: url("/repo/docs/x.md"))
        #expect(repo.trackedCallCount == 1)
    }
}
