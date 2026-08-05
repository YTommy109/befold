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

        let result = await GitDiffLoader(reader: reader).diff(forFileAt: file, in: root)

        #expect(result == .diff("@@ -1 +1 @@\n"))
        #expect(reader.calls == 1)
    }

    /// 走行中の取得は要求より前のツリーを読んでいるため相乗りできない(相乗りすると
    /// 保存直後の要求へ変更前の差分が返る)。重なった要求は、走行中の完了後に
    /// **1 回だけ**取り直してまとめて返す。git が同時に 2 つ走ることはない。
    @Test("重なった要求は走行後の 1 回の再取得にまとめられる")
    func collapsesOverlappingRequestsIntoOneRefetch() async {
        let reader = CountingDiffReader(result: .noChanges, delay: 0.2)
        let loader = GitDiffLoader(reader: reader)

        async let first = loader.diff(forFileAt: file, in: root)
        async let second = loader.diff(forFileAt: file, in: root)
        async let third = loader.diff(forFileAt: file, in: root)
        let results = await [first, second, third]

        #expect(results == [.noChanges, .noChanges, .noChanges])
        // 先行の 1 回 + 後から重なった 2 件をまとめた再取得 1 回。要求ごとには増えない。
        #expect(reader.calls == 2)
    }

    /// 走行中のタスクへ相乗りさせると、その結果は要求より前のツリーのもので、
    /// 再取得の契機も無いまま古い差分が表示され続ける(「保存したのに古い差分が出る」)。
    @Test("走行中に届いた要求へは、走行後に取り直した新しい結果を返す")
    func overlappingRequestGetsFreshResult() async {
        let reader = SequenceDiffReader(results: [.diff("旧"), .diff("新")], delay: 0.2)
        let loader = GitDiffLoader(reader: reader)

        async let running = loader.diff(forFileAt: file, in: root)
        async let overlapping = loader.diff(forFileAt: file, in: root)
        let results = await [running, overlapping]

        #expect(results[0] == .diff("旧"))
        #expect(results[1] == .diff("新"))
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
