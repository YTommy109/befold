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

/// 呼ばれるたびに次の結果を返すスタブ。「取得のたびに作業ツリーが変わっている」状況を作る。
/// 用意した結果を使い切ったら最後の値を返し続ける。
private final class SequenceDiffReader: GitDiffReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [GitFileDiff?]
    private var index = 0
    private let delay: TimeInterval

    /// 呼び出し回数。用意した結果を使い切っても増え続けるため、
    /// 「取り直したか」を結果の中身と独立に測れる。
    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }

    init(results: [GitFileDiff?], delay: TimeInterval = 0) {
        self.results = results
        self.delay = delay
    }

    func diff(forFileAt _: URL, in _: URL) -> GitFileDiff? {
        lock.lock()
        let result = results[min(index, results.count - 1)]
        index += 1
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
        let loader = GitDiffLoader(reader: reader)

        let result = await loader.diff(
            forFileAt: file, in: root, requestedAt: loader.takeRequestTicket()
        )

        #expect(result == .diff("@@ -1 +1 @@\n"))
        #expect(reader.calls == 1)
    }

    /// AC#1: 同じ契機(1 回のファイル変更イベント)から出た兄弟要求は、取得 1 回に合流する。
    /// 契機の時点でチケットを取っているため、先行の取得はどの要求より後に始まっており、
    /// 全員が相乗りできる。窓ごとにローダーを持つ・チケットを取得直前に取る、の
    /// どちらへ戻しても要求の数だけ git が起動してここが落ちる(TASK-325)。
    @Test("同じ契機から出た要求は 1 回の取得に合流する")
    func collapsesSiblingRequestsIntoOneFetch() async {
        let reader = CountingDiffReader(result: .noChanges, delay: 0.2)
        let loader = GitDiffLoader(reader: reader)
        // 3 窓が同じファイル変更イベントを受け取った状態。取得より前に順番が確定する。
        let tickets = (0 ..< 3).map { _ in loader.takeRequestTicket() }

        async let first = loader.diff(forFileAt: file, in: root, requestedAt: tickets[0])
        async let second = loader.diff(forFileAt: file, in: root, requestedAt: tickets[1])
        async let third = loader.diff(forFileAt: file, in: root, requestedAt: tickets[2])
        let results = await [first, second, third]

        #expect(results == [.noChanges, .noChanges, .noChanges])
        #expect(reader.calls == 1)
    }

    /// 走行中のタスクへ相乗りさせると、その結果は要求より前のツリーのもので、
    /// 再取得の契機も無いまま古い差分が表示され続ける(「保存したのに古い差分が出る」
    /// = TASK-321)。取得が始まった**後**に生まれた要求は、取り直した結果を受け取る。
    @Test("走行中に届いた要求へは、走行後に取り直した新しい結果を返す")
    func laterRequestGetsFreshResult() async {
        let reader = SequenceDiffReader(results: [.diff("旧"), .diff("新")], delay: 0.2)
        let loader = GitDiffLoader(reader: reader)

        async let running = loader.diff(
            forFileAt: file, in: root, requestedAt: loader.takeRequestTicket()
        )
        // 取得が始まってから 2 件目の要求を作る。始まる前にチケットを取ると
        // 兄弟要求(上のテスト)になってしまい、測りたい状況と別物になる。
        while reader.calls == 0 {
            await Task.yield()
        }
        async let later = loader.diff(
            forFileAt: file, in: root, requestedAt: loader.takeRequestTicket()
        )
        let results = await [running, later]

        #expect(results[0] == .diff("旧"))
        #expect(results[1] == .diff("新"))
        #expect(reader.calls == 2)
    }

    /// 作業ツリーの編集は `.git/index` を動かさないため、キャッシュすると必ず陳腐化する。
    /// 「2 回目も読み直す」ことが仕様であり、キャッシュを足したらここが落ちる。
    @Test("結果をキャッシュせず、要求のたびに読み直す")
    func doesNotCacheResults() async {
        let reader = CountingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)

        _ = await loader.diff(forFileAt: file, in: root, requestedAt: loader.takeRequestTicket())
        _ = await loader.diff(forFileAt: file, in: root, requestedAt: loader.takeRequestTicket())

        #expect(reader.calls == 2)
    }

    @Test("取得できなかった場合は nil を返す")
    func propagatesUnavailable() async {
        let reader = CountingDiffReader(result: nil)
        let loader = GitDiffLoader(reader: reader)

        let result = await loader.diff(
            forFileAt: file, in: root, requestedAt: loader.takeRequestTicket()
        )

        #expect(result == nil)
    }
}
