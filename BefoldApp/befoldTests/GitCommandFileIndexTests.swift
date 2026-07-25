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
