@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 指定したルートの列挙だけを合図があるまで止めるフェイク。ロックの粒度を観測するために使う。
/// ルート解決はファイルの親ディレクトリの親をルートとみなす（`/repo/d0/x.md` → `/repo`）。
/// ディレクトリを分けると同じルートでも解決がディレクトリごとに走るので、呼び出しが
/// ルートキーのロックの手前まで来たことを `rootLookupCount` で数えられる。
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
    private let rootLookups = LockedBox(0)

    /// ルート解決が呼ばれた回数（解決はディレクトリごとにキャッシュされる）。
    var rootLookupCount: Int {
        rootLookups.get()
    }

    init(blocking blockedRoot: URL) {
        blockedRootPath = blockedRoot.path
    }

    func trackedCallCount(for root: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return callCountByRoot[root.path] ?? 0
    }

    func root(forFileAt url: URL) -> GitRootLookup {
        rootLookups.update { $0 += 1 }
        return .root(url.deletingLastPathComponent().deletingLastPathComponent())
    }

    func trackedFiles(at root: URL) -> [URL]? {
        lock.lock()
        callCountByRoot[root.path, default: 0] += 1
        lock.unlock()
        if root.path == blockedRootPath {
            enteredBlockedEnumeration.set(true)
            releaseBlockedEnumeration.waitUntilOpen()
        }
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
        Task {
            _ = await withBlockingWork {
                sut.trackedFileIndex(forFileAt: slowRoot.appendingPathComponent("d/x.md"))
            }
        }
        await waitUntil { repo.didEnterBlockedEnumeration }

        // 別リポジトリの解決を試みる。ロックがリポジトリ横断だと、ここが解放まで返らない。
        let otherResolved = LockedBox(false)
        Task {
            _ = await withBlockingWork {
                sut.trackedFileIndex(forFileAt: url("/other-repo/d/y.md"))
            }
            otherResolved.set(true)
        }

        await waitUntil { otherResolved.get() }
        #expect(otherResolved.get(), "別リポジトリの解決が遅いリポジトリに巻き込まれてブロックされている")
    }

    /// 同一ルートへの同時呼び出しが直列化されないと、N ウィンドウぶんの `git ls-files` が
    /// 同時に走り、索引の構築(候補数に比例した正規化)も重複する。
    ///
    /// 1 本目の列挙を止めたまま、残りの呼び出しがルート解決を終える（= ルートキーのロックの
    /// 手前まで来る）のを数えてから解放する。直列化が無ければ、残りは解放前にキャッシュを
    /// 外して列挙へ入る。ロック（`rootLocks.withLock`）を外すと落ちることを実測で確認している。
    @Test("同一ルートへの同時呼び出しでは列挙が 1 度しか走らない", testTimeLimit())
    func concurrentCallsForSameRootEnumerateOnce() async {
        let root = url("/repo")
        let repo = BlockingRepository(blocking: root)
        let sut = GitCommandFileIndex(repository: repo)
        defer { repo.releaseBlockedEnumeration.open() }
        let callers = 4

        let finished = LockedBox(0)
        for caller in 0 ..< callers {
            Task {
                _ = await withBlockingWork {
                    sut.trackedFileIndex(forFileAt: root.appendingPathComponent("d\(caller)/x.md"))
                }
                finished.update { $0 += 1 }
            }
        }
        await waitUntil { repo.didEnterBlockedEnumeration && repo.rootLookupCount == callers }
        repo.releaseBlockedEnumeration.open()

        await waitUntil { finished.get() == callers }
        #expect(repo.trackedCallCount(for: root) == 1, "同一ルートの列挙が重複して走っている")
    }
}
