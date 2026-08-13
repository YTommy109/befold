@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// テスト用のリポジトリルート(実在しなくてよい。ルート解決はフェイクが返す)。
/// Sendable なルート解決クロージャから参照するため、MainActor 隔離される型の
/// 静的プロパティではなくファイルスコープに置く。
private let testRepositoryRoot = URL(fileURLWithPath: "/repos/befold")
private let testIndexURL = URL(fileURLWithPath: "/repos/befold/.git/index")

/// GitStatusStore のキャッシュ・縮退・重複実行の畳み込みを、実 git を起動せずに検証する。
@Suite
@MainActor
struct GitStatusStoreTests {
    /// Sendable クロージャ(ルート解決)から参照するため、MainActor 隔離される
    /// 型の静的プロパティではなくファイルスコープの定数に置く。
    private let root = testRepositoryRoot
    private let directory = testRepositoryRoot.appendingPathComponent("docs")

    /// 呼び出し回数を数え、返す結果を差し替えられるフェイク。
    /// `GitStatusReading` はメイン外(detached)から呼ばれるためロックで直列化する
    /// (`GitCommandFileIndexTests.FakeRepository` と同じ方式)。
    private final class FakeReader: GitStatusReading, @unchecked Sendable {
        private let lock = NSLock()
        private var results: [GitStatusSnapshot?]
        private var calls = 0
        /// 呼び出しの開始を通知する。nil なら通知しない。
        private let onCall: (@Sendable (Int) -> Void)?
        /// 呼び出しの中で待機する(nil なら待たない)。
        private let block: BlockingGate?

        /// `indexFingerprint(forRepositoryAt:)` が返す値。差し替えて index の動きを模す。
        private var fingerprint: Date?
        private var fingerprintCalls = 0

        init(
            results: [GitStatusSnapshot?],
            fingerprint: Date? = nil,
            onCall: (@Sendable (Int) -> Void)? = nil,
            block: BlockingGate? = nil
        ) {
            self.results = results
            self.fingerprint = fingerprint
            self.onCall = onCall
            self.block = block
        }

        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls
        }

        func setFingerprint(_ date: Date?) {
            lock.lock(); defer { lock.unlock() }
            fingerprint = date
        }

        func indexFingerprint(forRepositoryAt _: URL) -> Date? {
            lock.lock(); defer { lock.unlock() }
            fingerprintCalls += 1
            return fingerprint
        }

        func status(forRepositoryAt _: URL) -> GitStatusSnapshot? {
            lock.lock()
            calls += 1
            let index = min(calls - 1, results.count - 1)
            let result = results.isEmpty ? nil : results[index]
            let calls = calls
            lock.unlock()
            onCall?(calls)
            if let block { block.wait("FakeReader.status") }
            return result
        }
    }

    private func snapshot(
        _ statuses: [String: GitFileStatus], indexFingerprint: Date? = nil
    ) -> GitStatusSnapshot {
        GitStatusSnapshot(
            statuses: statuses, indexFingerprint: indexFingerprint, indexURL: testIndexURL
        )
    }

    private func makeStore(_ reader: FakeReader, resolvesRoot: Bool = true) -> GitStatusStore {
        GitStatusStore(
            reader: reader,
            resolveRepositoryRoot: { _ in resolvesRoot ? testRepositoryRoot : nil }
        )
    }

    private var modifiedStatus: [String: GitFileStatus] {
        ["/repos/befold/docs/a.md": GitFileStatus(indexChange: nil, worktreeChange: .modified)]
    }

    @Test("リポジトリ外(ルート未解決)では git を呼ばず空を返す")
    func returnsEmptyWithoutCallingGitOutsideRepository() async {
        let reader = FakeReader(results: [snapshot(modifiedStatus)])
        let store = makeStore(reader, resolvesRoot: false)

        let statuses = await store.statuses(forDirectoryAt: directory).statuses

        #expect(statuses.isEmpty)
        #expect(reader.callCount == 0)
    }

    @Test("取得した状態をそのまま返す")
    func returnsSnapshot() async {
        let reader = FakeReader(results: [snapshot(modifiedStatus)])
        let store = makeStore(reader)

        let statuses = await store.statuses(forDirectoryAt: directory).statuses

        #expect(statuses == modifiedStatus)
    }

    /// 状態は編集のたびに変わるため、キャッシュは「取れなかったときの保険」であって
    /// 再取得を止める根拠ではない。refresh のたびに取り直せることを固定する。
    @Test("refresh のたびに取り直し、最新の結果に差し替わる")
    func refetchesOnEveryRequest() async {
        let updated = ["/repos/befold/docs/b.md": GitFileStatus(indexChange: .added, worktreeChange: nil)]
        let reader = FakeReader(results: [snapshot(modifiedStatus), snapshot(updated)])
        let store = makeStore(reader)

        _ = await store.statuses(forDirectoryAt: directory)
        let second = await store.statuses(forDirectoryAt: directory).statuses

        #expect(second == updated)
        #expect(reader.callCount == 2)
    }

    /// `.unavailable`(git を動かせなかった)は答えが不明なだけなので、キャッシュを
    /// 上書きして機能を殺してはならない。直前に取れていた状態を出し続ける。
    @Test("git を動かせなかった場合は直前のキャッシュを維持して返す")
    func keepsPreviousSnapshotWhenGitIsUnavailable() async {
        let reader = FakeReader(results: [snapshot(modifiedStatus), nil])
        let store = makeStore(reader)

        _ = await store.statuses(forDirectoryAt: directory)
        let afterFailure = await store.statuses(forDirectoryAt: directory).statuses

        #expect(afterFailure == modifiedStatus)
    }

    @Test("初回から git を動かせなければ空に縮退する")
    func degradesToEmptyWhenGitIsUnavailableFromTheStart() async {
        let reader = FakeReader(results: [nil])
        let store = makeStore(reader)

        let statuses = await store.statuses(forDirectoryAt: directory).statuses

        #expect(statuses.isEmpty)
    }

    /// `.git` 配下への書き込み通知は index 以外の理由でも来る。index が動いていないなら
    /// status を取り直す理由はないので、git を起こさずキャッシュを返す(TASK-186.2)。
    @Test("onlyIfIndexChanged: fingerprint 無変化なら git を呼ばずキャッシュを返す")
    func skipsGitWhenIndexFingerprintIsUnchanged() async {
        let stamp = Date(timeIntervalSince1970: 1000)
        let reader = FakeReader(results: [snapshot(modifiedStatus, indexFingerprint: stamp)], fingerprint: stamp)
        let store = makeStore(reader)
        _ = await store.statuses(forDirectoryAt: directory)

        let result = await store.statuses(forDirectoryAt: directory, policy: .onlyIfIndexChanged)

        #expect(result.statuses == modifiedStatus)
        #expect(result.indexURL == testIndexURL)
        #expect(reader.callCount == 1)
    }

    @Test("onlyIfIndexChanged: fingerprint が変わっていれば取り直す")
    func refetchesWhenIndexFingerprintChanged() async {
        let first = Date(timeIntervalSince1970: 1000)
        let second = Date(timeIntervalSince1970: 2000)
        let staged = ["/repos/befold/docs/a.md": GitFileStatus(indexChange: .modified, worktreeChange: nil)]
        let reader = FakeReader(
            results: [snapshot(modifiedStatus, indexFingerprint: first), snapshot(staged, indexFingerprint: second)],
            fingerprint: first
        )
        let store = makeStore(reader)
        _ = await store.statuses(forDirectoryAt: directory)
        reader.setFingerprint(second)

        let result = await store.statuses(forDirectoryAt: directory, policy: .onlyIfIndexChanged)

        #expect(result.statuses == staged)
        #expect(reader.callCount == 2)
    }

    /// キャッシュが無い(初回)なら、fingerprint を見るまでもなく取りに行く。
    @Test("onlyIfIndexChanged: キャッシュが無ければ取得する")
    func fetchesOnFirstRequestEvenWithIndexPolicy() async {
        let reader = FakeReader(results: [snapshot(modifiedStatus)])
        let store = makeStore(reader)

        let result = await store.statuses(forDirectoryAt: directory, policy: .onlyIfIndexChanged)

        #expect(result.statuses == modifiedStatus)
        #expect(reader.callCount == 1)
    }

    /// 同じルートへの要求が重なったときに git を 2 回起こさないこと(in-flight の畳み込み)。
    ///
    /// 競合は固定 sleep ではなくゲートで決定的に組み立てる:
    /// 1. 1 本目を発行し、reader の中で足止めする(この時点で in-flight 登録は済んでいる)。
    /// 2. 2 本目のルート解決完了をゲートで待つ。2 本目のメインアクターへの復帰は
    ///    この時点で既に enqueue されており、足止め解除後に走る 1 本目の完了より先に処理される。
    /// 3. 足止めを解除し、両方の完了を待つ。畳み込みが効いていれば reader は 1 回しか呼ばれない。
    @Test("同一ルートへの同時要求は git 実行 1 回に畳み込まれる")
    func foldsConcurrentRequestsForSameRoot() async {
        let readerEntered = AsyncGate()
        let secondRootResolved = AsyncGate()
        let release = BlockingGate()
        let reader = FakeReader(
            results: [snapshot(modifiedStatus)],
            onCall: { _ in readerEntered.open() },
            block: release
        )
        let rootResolutions = LockedBox(0)
        let store = GitStatusStore(
            reader: reader,
            resolveRepositoryRoot: { _ in
                rootResolutions.update { $0 += 1 }
                if rootResolutions.get() == 2 { secondRootResolved.open() }
                return testRepositoryRoot
            }
        )

        let first = Task { await store.statuses(forDirectoryAt: directory).statuses }
        await readerEntered.wait()
        let second = Task { await store.statuses(forDirectoryAt: directory).statuses }
        await secondRootResolved.wait()
        release.open()

        #expect(await first.value == modifiedStatus)
        #expect(await second.value == modifiedStatus)
        #expect(reader.callCount == 1)
    }
}
