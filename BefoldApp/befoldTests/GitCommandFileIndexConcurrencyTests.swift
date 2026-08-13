@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 指定したルートの列挙だけを合図があるまで止めるフェイク。ロックの粒度を観測するために使う。
/// `trackedFiles` はディレクトリをそのままルートとみなす MultiRepoFake と同じ規約。
private final class BlockingRepository: GitRepositoryReading, @unchecked Sendable {
    /// 列挙を止めるルートのパス。ここ以外のルートは即座に返す。
    private let blockedRootPath: String
    /// 止めたルートの列挙に入ったことを呼び出し側へ知らせる。
    /// テストは async 文脈で待つため、セマフォではなくポーリング可能なフラグにする。
    private let enteredBlockedEnumeration = LockedBox(false)
    /// これを open するまで止めたルートの列挙は返らない。
    /// wait するのはフェイクを走らせているバックグラウンドスレッド側のみ。
    let releaseBlockedEnumeration = BlockingGate()

    var didEnterBlockedEnumeration: Bool {
        enteredBlockedEnumeration.get()
    }

    private let lock = NSLock()
    private var callCountByRoot: [String: Int] = [:]

    init(blocking blockedRoot: URL) {
        blockedRootPath = blockedRoot.path
    }

    func trackedCallCount(for root: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return callCountByRoot[root.path] ?? 0
    }

    func root(forFileAt url: URL) -> GitRootLookup {
        .root(url.deletingLastPathComponent())
    }

    func trackedFiles(at root: URL) -> [URL]? {
        lock.lock()
        callCountByRoot[root.path, default: 0] += 1
        lock.unlock()
        if root.path == blockedRootPath {
            enteredBlockedEnumeration.set(true)
            releaseBlockedEnumeration.wait("BlockingRepository.trackedFiles")
        }
        return [root.appendingPathComponent("a.swift")]
    }

    func indexFingerprint(at _: URL) -> Date? {
        Date(timeIntervalSince1970: 1)
    }
}

/// 列挙に一定時間かかるフェイク。同一ルートへの同時呼び出しが重なる窓を作り、
/// in-flight 管理が無ければ列挙が重複することを観測できるようにする。
private final class SlowRepository: GitRepositoryReading, @unchecked Sendable {
    private let enumerationDelay: TimeInterval
    private let lock = NSLock()
    private var _trackedCallCount = 0

    var trackedCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _trackedCallCount
    }

    init(enumerationDelay: TimeInterval) {
        self.enumerationDelay = enumerationDelay
    }

    func root(forFileAt url: URL) -> GitRootLookup {
        .root(url.deletingLastPathComponent())
    }

    func trackedFiles(at root: URL) -> [URL]? {
        lock.lock()
        _trackedCallCount += 1
        lock.unlock()
        Thread.sleep(forTimeInterval: enumerationDelay)
        return [root.appendingPathComponent("a.swift")]
    }

    func indexFingerprint(at _: URL) -> Date? {
        Date(timeIntervalSince1970: 1)
    }
}

/// ロックの粒度に関する検証。GitCommandFileIndex は全ウィンドウで 1 インスタンスを
/// 共有するため、`git` subprocess を待つ間にどのロックを握っているかが
/// 「無関係なリポジトリのウィンドウまで止まるか」を直接決める。
struct GitCommandFileIndexConcurrencyTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    /// 本番では全ウィンドウが 1 インスタンスを共有するため、ロックの粒度がリポジトリ横断だと
    /// 1 つの遅い `git ls-files` が無関係なリポジトリのウィンドウまで最大 15 秒
    /// (timeout 10 秒 + terminationGrace 5 秒)止める。異なるルートの呼び出しが
    /// 互いに待たないことを固定する。
    @Test("遅いリポジトリの列挙中でも別リポジトリの解決は完了する", testTimeLimit())
    func slowEnumerationDoesNotBlockOtherRepositories() async {
        let slowRoot = url("/slow-repo")
        let repo = BlockingRepository(blocking: slowRoot)
        let sut = GitCommandFileIndex(repository: repo)
        // 解放し忘れでバックグラウンドスレッドが残らないよう、経路によらず必ず解放する。
        defer { repo.releaseBlockedEnumeration.open() }

        // 遅いリポジトリの列挙を進行中のまま止める。
        Task.detached { _ = sut.trackedFileIndex(forFileAt: slowRoot.appendingPathComponent("x.md")) }
        await waitUntil { repo.didEnterBlockedEnumeration }

        // 別リポジトリの解決を試みる。ロックがリポジトリ横断だと、ここが解放まで返らない。
        let otherResolved = LockedBox(false)
        Task.detached {
            _ = sut.trackedFileIndex(forFileAt: url("/other-repo").appendingPathComponent("y.md"))
            otherResolved.set(true)
        }

        await waitUntil { otherResolved.get() }
        #expect(otherResolved.get(), "別リポジトリの解決が遅いリポジトリに巻き込まれてブロックされている")
    }

    /// 同一ルートへの同時呼び出しが直列化されないと、N ウィンドウぶんの `git ls-files` が
    /// 同時に走り、索引の構築(候補数に比例した正規化)も重複する。
    @Test("同一ルートへの同時呼び出しでは列挙が 1 度しか走らない", testTimeLimit())
    func concurrentCallsForSameRootEnumerateOnce() async {
        let repo = SlowRepository(enumerationDelay: 0.2)
        let sut = GitCommandFileIndex(repository: repo)
        let root = url("/repo")

        let finished = LockedBox(0)
        for _ in 0 ..< 4 {
            Task.detached {
                _ = sut.trackedFileIndex(forFileAt: root.appendingPathComponent("x.md"))
                finished.update { $0 += 1 }
            }
        }

        await waitUntil { finished.get() == 4 }
        #expect(repo.trackedCallCount == 1, "同一ルートの列挙が重複して走っている")
    }
}
