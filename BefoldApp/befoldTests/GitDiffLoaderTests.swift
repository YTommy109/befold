@testable import befold
import BefoldKit
import Foundation
import Testing

/// 呼び出し回数を数えるスタブ。git は起こさない。
private final class CountingDiffReader: GitDiffReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private let result: GitFileDiff?
    private let delay: TimeInterval

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    init(result: GitFileDiff?, delay: TimeInterval = 0) {
        self.result = result
        self.delay = delay
    }

    func diff(forFileAt _: URL, in _: URL) -> GitFileDiff? {
        lock.lock()
        _calls += 1
        lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return result
    }
}

@MainActor
struct GitDiffLoaderTests {
    private let root = URL(fileURLWithPath: "/tmp/repo")
    private let file = URL(fileURLWithPath: "/tmp/repo/a.swift")

    @Test("読み取り結果をそのまま返す")
    func returnsReaderResult() async {
        let reader = CountingDiffReader(result: .diff("@@ -1 +1 @@\n"))

        let result = await GitDiffLoader(reader: reader).diff(forFileAt: file, in: root)

        #expect(result == .diff("@@ -1 +1 @@\n"))
        #expect(reader.calls == 1)
    }

    /// 同じファイルへの要求が重なったとき git を二重起動しない。
    @Test("走行中の要求が重なったら 1 回に畳まれる")
    func collapsesConcurrentRequests() async {
        let reader = CountingDiffReader(result: .noChanges, delay: 0.2)
        let loader = GitDiffLoader(reader: reader)

        async let first = loader.diff(forFileAt: file, in: root)
        async let second = loader.diff(forFileAt: file, in: root)
        let results = await [first, second]

        #expect(results == [.noChanges, .noChanges])
        #expect(reader.calls == 1)
    }

    /// 作業ツリーの編集は `.git/index` を動かさないため、キャッシュすると必ず陳腐化する。
    /// 「2 回目も読み直す」ことが仕様であり、キャッシュを足したらここが落ちる。
    @Test("結果をキャッシュせず、要求のたびに読み直す")
    func doesNotCacheResults() async {
        let reader = CountingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)

        _ = await loader.diff(forFileAt: file, in: root)
        _ = await loader.diff(forFileAt: file, in: root)

        #expect(reader.calls == 2)
    }

    @Test("取得できなかった場合は nil を返す")
    func propagatesUnavailable() async {
        let reader = CountingDiffReader(result: nil)

        #expect(await GitDiffLoader(reader: reader).diff(forFileAt: file, in: root) == nil)
    }
}
