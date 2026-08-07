@testable import befold
import BefoldKit
import Foundation
import Testing

// 呼び出し回数を数えるスタブは DiffTestSupport.swift の RecordingDiffReader を共有する。

@MainActor
struct GitDiffLoaderTests {
    private let root = URL(fileURLWithPath: "/tmp/repo")
    private let file = URL(fileURLWithPath: "/tmp/repo/a.swift")

    @Test("読み取り結果をそのまま返す")
    func returnsReaderResult() async {
        let reader = RecordingDiffReader(result: .diff("@@ -1 +1 @@\n"))
        let loader = GitDiffLoader(reader: reader)

        let result = await loader.diff(forFileAt: file, resolvingRootWith: resolving(root)).value

        #expect(result == .diff("@@ -1 +1 @@\n"))
        #expect(reader.callCount == 1)
    }

    /// AC#1: 同じ契機(1 回のファイル変更イベント)から出た兄弟要求は、取得 1 回に合流する。
    /// 登録は契機のターンで同期に済むため、先行の取得はまだツリーを読み始めておらず
    /// 全員が相乗りできる。窓ごとにローダーを持つ形へ戻すと、要求の数だけ git が
    /// 起動してここが落ちる(TASK-325)。
    @Test("同じ契機から出た要求は 1 回の取得に合流する")
    func collapsesSiblingRequestsIntoOneFetch() async {
        let reader = RecordingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)

        // 3 窓が同じファイル変更イベントを受け取った状態。登録はこの 1 ターンで終わる。
        let fetches = (0 ..< 3).map { _ in
            loader.diff(forFileAt: file, resolvingRootWith: resolving(root))
        }
        var results: [GitFileDiff?] = []
        for fetch in fetches {
            await results.append(fetch.value)
        }

        #expect(results == [.noChanges, .noChanges, .noChanges])
        #expect(reader.callCount == 1)
    }

    /// AC#2: 兄弟要求の合流は**実行順に依存しない**。負荷で 1 件目が完走してから
    /// 2 件目が動き出しても、同じ契機で登録された以上 1 回に合流する。
    /// 合流の可否を「走行中の取得が存在するか」で決める形へ戻すと、完了済みの取得には
    /// 相乗りできず要求の数だけ git が起動してここが落ちる(TASK-346)。
    @Test("同じ契機の要求は、逐次に処理されても 1 回の取得に合流する")
    func collapsesSiblingRequestsEvenWhenSerialized() async {
        let reader = RecordingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)

        // 2 窓が同じファイル変更イベントを受け取った状態。登録はこの 1 ターン。
        let first = loader.diff(forFileAt: file, resolvingRootWith: resolving(root))
        let second = loader.diff(forFileAt: file, resolvingRootWith: resolving(root))
        // 1 件目を完走させてから 2 件目を待つ。TSan や高負荷でメインアクターが詰まると
        // 実際にこの順序になる(TASK-327 の実測では 5〜8 秒到達しない)。
        _ = await first.value
        _ = await second.value

        #expect(reader.callCount == 1)
    }

    /// 走行中のタスクへ相乗りさせると、その結果は要求より前のツリーのもので、
    /// 再取得の契機も無いまま古い差分が表示され続ける(「保存したのに古い差分が出る」
    /// = TASK-321)。読み始めた**後**に登録された要求は、取り直した結果を受け取る。
    @Test("読み始めた後に届いた要求へは、取り直した新しい結果を返す")
    func laterRequestGetsFreshResult() async {
        let reader = SequenceDiffReader(results: [.diff("旧"), .diff("新")])
        let loader = GitDiffLoader(reader: reader)

        let running = loader.diff(forFileAt: file, resolvingRootWith: resolving(root))
        // ツリーを読み始めるまで待つ。読み始める前に登録すると兄弟要求(上のテスト)に
        // なってしまい、測りたい状況と別物になる。
        while reader.calls == 0 {
            await Task.yield()
        }
        let later = loader.diff(forFileAt: file, resolvingRootWith: resolving(root))

        #expect(await running.value == .diff("旧"))
        #expect(await later.value == .diff("新"))
        #expect(reader.calls == 2)
    }

    /// 作業ツリーの編集は `.git/index` を動かさないため、キャッシュすると必ず陳腐化する。
    /// 「2 回目も読み直す」ことが仕様であり、キャッシュを足したらここが落ちる。
    @Test("結果をキャッシュせず、契機のたびに読み直す")
    func doesNotCacheResults() async {
        let reader = RecordingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)

        // 別々の契機。1 件目を待ってから 2 件目を登録するので合流しない。
        _ = await loader.diff(forFileAt: file, resolvingRootWith: resolving(root)).value
        _ = await loader.diff(forFileAt: file, resolvingRootWith: resolving(root)).value

        #expect(reader.callCount == 2)
    }

    @Test("取得できなかった場合は nil を返す")
    func propagatesUnavailable() async {
        let reader = RecordingDiffReader(result: nil)
        let loader = GitDiffLoader(reader: reader)

        let result = await loader.diff(forFileAt: file, resolvingRootWith: resolving(root)).value

        #expect(result == nil)
    }

    /// リポジトリルートを解決できないファイルでは git を起こさない。
    /// ルート解決をローダーの中へ移したため、ここが呼び出し側から見えなくなった。
    @Test("リポジトリルートを解決できなければ読み取りを行わず nil を返す")
    func skipsFetchWhenRootIsUnresolvable() async {
        let reader = RecordingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)

        let result = await loader.diff(forFileAt: file, resolvingRootWith: { nil }).value

        #expect(result == nil)
        #expect(reader.callCount == 0)
    }

    /// ルートを解決できなかった契機が、以後の取得を詰まらせないこと。
    /// 登録の取り下げを取得の成否に紐づけると、ここで永久に相乗り待ちになる。
    @Test("ルートを解決できなかった後も、次の契機の取得は走る")
    func recoversAfterUnresolvableRoot() async {
        let reader = RecordingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)

        _ = await loader.diff(forFileAt: file, resolvingRootWith: { nil }).value
        let result = await loader.diff(forFileAt: file, resolvingRootWith: resolving(root)).value

        #expect(result == .noChanges)
        #expect(reader.callCount == 1)
    }

    /// 別ファイルの取得は互いに合流しない(キーがファイルごとであることの固定)。
    @Test("別のファイルの要求は合流しない")
    func doesNotCollapseAcrossFiles() async {
        let reader = RecordingDiffReader(result: .noChanges)
        let loader = GitDiffLoader(reader: reader)
        let other = URL(fileURLWithPath: "/tmp/repo/b.swift")

        let first = loader.diff(forFileAt: file, resolvingRootWith: resolving(root))
        let second = loader.diff(forFileAt: other, resolvingRootWith: resolving(root))
        _ = await first.value
        _ = await second.value

        #expect(reader.callCount == 2)
    }

    /// ルート解決はメインアクターの外で行う契約(TASK-322)。同期の `git rev-parse` を
    /// メインアクター上へ戻すと、遅いボリュームで UI が止まる。
    private func resolving(_ root: URL) -> @Sendable () -> URL? {
        { root }
    }
}
