@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// `warm` は別スレッドから `trackedFiles(at:)` を呼ぶため、このフェイクへの
/// アクセスはロックで直列化して race を避ける。
private final class FakeRepository: GitRepositoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _stubRoot: GitRootLookup
    private var _fingerprint: Date?
    private var _files: [URL]?
    private var _trackedCallCount = 0
    private var _rootCallCount = 0

    var stubRoot: GitRootLookup {
        get { lock.lock(); defer { lock.unlock() }; return _stubRoot }
        set { lock.lock(); defer { lock.unlock() }; _stubRoot = newValue }
    }

    var rootCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _rootCallCount
    }

    var fingerprint: Date? {
        get { lock.lock(); defer { lock.unlock() }; return _fingerprint }
        set { lock.lock(); defer { lock.unlock() }; _fingerprint = newValue }
    }

    /// nil は「git を実行できなかった」を表す(追跡ファイル 0 件と区別する)。
    var files: [URL]? {
        get { lock.lock(); defer { lock.unlock() }; return _files }
        set { lock.lock(); defer { lock.unlock() }; _files = newValue }
    }

    var trackedCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _trackedCallCount
    }

    init(root: GitRootLookup, fingerprint: Date?, files: [URL]?) {
        _stubRoot = root
        _fingerprint = fingerprint
        _files = files
    }

    func root(forFileAt url: URL) -> GitRootLookup {
        lock.lock(); defer { lock.unlock() }
        _rootCallCount += 1
        return _stubRoot
    }

    func trackedFiles(at root: URL) -> [URL]? {
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

    func root(forFileAt url: URL) -> GitRootLookup {
        .root(url.deletingLastPathComponent())
    }

    func trackedFiles(at root: URL) -> [URL]? {
        lock.lock()
        callCountByRoot[root.path, default: 0] += 1
        lock.unlock()
        return [root.appendingPathComponent("a.swift")]
    }

    func indexFingerprint(at root: URL) -> Date? {
        Date(timeIntervalSince1970: 1)
    }
}

/// 問い合わせに使われた URL からリポジトリルートを導くフェイク。
/// 実際の `rev-parse` と違い、symlink 経由で問い合わせれば symlink 表記のルートを返す
/// ため、キャッシュキーの正規化が効いていないと同じリポジトリが別エントリに割れる。
private final class PathDerivedRepository: GitRepositoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _rootCallCount = 0
    private var _trackedCallCount = 0

    var rootCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _rootCallCount
    }

    var trackedCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _trackedCallCount
    }

    func root(forFileAt url: URL) -> GitRootLookup {
        lock.lock(); defer { lock.unlock() }
        _rootCallCount += 1
        return .root(url.deletingLastPathComponent())
    }

    func trackedFiles(at root: URL) -> [URL]? {
        lock.lock(); defer { lock.unlock() }
        _trackedCallCount += 1
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

    /// 索引は候補一覧を公開しないため、書かれたパスの解決結果という観測できる振る舞いで中身を見る。
    private func resolution(_ index: SuffixPathIndex?, of writtenPath: String) -> URL? {
        index?.bestMatch(writtenPath: writtenPath, baseURL: url("/repo/docs/x.md"))
    }

    @Test("追跡ファイルの索引を返す")
    func returnsTrackedFileIndex() {
        let repo = FakeRepository(
            root: .root(url("/repo")),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)
        let index = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        #expect(resolution(index, of: "a.swift") == url("/repo/a.swift"))
    }

    @Test("git 管理外は nil")
    func returnsNilOutsideRepo() {
        let repo = FakeRepository(root: .notARepository, fingerprint: nil, files: [])
        #expect(GitCommandFileIndex(repository: repo).trackedFileIndex(forFileAt: url("/x/y.md")) == nil)
    }

    /// 索引の構築は列挙(`trackedFiles(at:)`)の直後の 1 箇所だけで行うため、列挙回数が
    /// そのまま索引の構築回数になる。解決バッチのたびに索引を作り直していた退行
    /// (候補数に比例した正規化が毎回走る)は、この列挙回数として現れる。
    @Test("同一 fingerprint では再列挙も索引の再構築もしない(キャッシュ命中)")
    func cachesWhileFingerprintUnchanged() {
        let repo = FakeRepository(
            root: .root(url("/repo")),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)
        // 別ファイルの表示(＝別の解決バッチ)を 2 回ぶん通す。
        let first = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        let second = sut.trackedFileIndex(forFileAt: url("/repo/docs/y.md"))
        #expect(repo.trackedCallCount == 1)
        // 2 度目も同じ内容の索引が返る(キャッシュ命中で空を返していない)。
        #expect(resolution(first, of: "a.swift") == url("/repo/a.swift"))
        #expect(resolution(second, of: "a.swift") == url("/repo/a.swift"))
    }

    @Test("fingerprint が変われば再列挙する(無効化)")
    func refetchesWhenFingerprintChanges() {
        let repo = FakeRepository(
            root: .root(url("/repo")),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)
        _ = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        repo.fingerprint = Date(timeIntervalSince1970: 2) // 外部の checkout / commit 相当
        repo.files = [url("/repo/a.swift"), url("/repo/b.swift")]
        let after = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        #expect(repo.trackedCallCount == 2)
        // 再列挙後に増えたファイルが索引にも反映されている(索引ごと作り直されている)。
        #expect(resolution(after, of: "b.swift") == url("/repo/b.swift"))
    }

    /// rev-parse を実行できなかっただけの結果を「git 管理外」として覚えると、起動直後の
    /// 高負荷などで 1 度タイムアウトしただけで、そのディレクトリはアプリ寿命の間ずっと
    /// リンク化されなくなる。確定した答えだけを覚えることを固定する。
    @Test("rev-parse が実行不能なら判定を覚えず、次回やり直す")
    func retriesRootLookupAfterUndeterminedResult() {
        let repo = FakeRepository(root: .undetermined, fingerprint: nil, files: [url("/repo/a.swift")])
        let sut = GitCommandFileIndex(repository: repo)

        #expect(sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md")) == nil)

        // git が復帰した後は、覚えた失敗に邪魔されず解決できる。
        repo.stubRoot = .root(url("/repo"))
        repo.fingerprint = Date(timeIntervalSince1970: 1)
        let index = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        #expect(resolution(index, of: "a.swift") == url("/repo/a.swift"))
        #expect(repo.rootCallCount == 2, "判定不能をキャッシュして再問い合わせしていない")
    }

    /// ls-files が実行できなかったときに空の索引を今の fingerprint で覚えると、次に commit 等で
    /// index が動くまでそのリポジトリのリンク化が丸ごと止まる。覚えないこと、
    /// そして手元に前回の索引があればそれを返してリンクを生かすことを固定する。
    @Test("ls-files が実行不能なら空を覚えず、前回の索引を返して次回やり直す")
    func keepsStaleIndexWhenEnumerationFails() {
        let repo = FakeRepository(
            root: .root(url("/repo")),
            fingerprint: Date(timeIntervalSince1970: 1),
            files: [url("/repo/a.swift")]
        )
        let sut = GitCommandFileIndex(repository: repo)
        _ = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))

        // 外部の commit で fingerprint が変わり、再列挙が git のタイムアウトで失敗する。
        repo.fingerprint = Date(timeIntervalSince1970: 2)
        repo.files = nil
        let duringFailure = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        #expect(resolution(duringFailure, of: "a.swift") == url("/repo/a.swift"), "前回の索引が失われている")

        // git が復帰したら、覚えていた古い索引ではなく新しい列挙結果に更新される。
        repo.files = [url("/repo/a.swift"), url("/repo/b.swift")]
        let afterRecovery = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        #expect(resolution(afterRecovery, of: "b.swift") == url("/repo/b.swift"), "失敗を覚えて再列挙していない")
    }

    /// この索引はアプリ寿命で生きるため、上限が無いと開いたことのある全リポジトリの
    /// 照合索引を抱え続ける。上限超過分が(索引ごと)捨てられることを固定する。
    @Test("保持するリポジトリ数には上限があり、古いものから捨てられる")
    func evictsLeastRecentlyUsedRoots() {
        let repo = MultiRepoFake()
        let sut = GitCommandFileIndex(repository: repo)
        let limit = GitCommandFileIndex.maxCachedRoots
        let roots = (1 ... limit + 1).map { url("/repo\($0)") }

        // 上限ちょうどまで埋める。
        for root in roots.prefix(limit) {
            _ = sut.trackedFileIndex(forFileAt: root.appendingPathComponent("x.md"))
        }
        // どれも再列挙されない(全部キャッシュに載っている)。
        for root in roots.prefix(limit) {
            _ = sut.trackedFileIndex(forFileAt: root.appendingPathComponent("x.md"))
            #expect(repo.trackedCallCount(for: root) == 1)
        }

        // 上限を 1 つ超えると、最も古い roots[0] が押し出される。
        _ = sut.trackedFileIndex(forFileAt: roots[limit].appendingPathComponent("x.md"))

        _ = sut.trackedFileIndex(forFileAt: roots[0].appendingPathComponent("x.md"))
        #expect(repo.trackedCallCount(for: roots[0]) == 2, "追い出されたはずのルートが再列挙されていない")
        _ = sut.trackedFileIndex(forFileAt: roots[limit].appendingPathComponent("x.md"))
        #expect(repo.trackedCallCount(for: roots[limit]) == 1, "直近のルートまで捨てている")
    }

    /// 同じディレクトリを symlink 経由と実パスの両方から開いても、キャッシュは
    /// 1 エントリに集約される(パスの同一性キーは URL.normalizedPathKey が単一情報源)。
    /// 集約されないと同じリポジトリに対して rev-parse と ls-files が二重に走る。
    @Test("symlink 経由と実パスは同じキャッシュエントリに集約される")
    func sharesCacheBetweenSymlinkedAndRealPaths() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedDirectory()
        let repo = PathDerivedRepository()
        let sut = GitCommandFileIndex(repository: repo)

        _ = sut.trackedFileIndex(forFileAt: real.appendingPathComponent("x.md"))
        _ = sut.trackedFileIndex(forFileAt: link.appendingPathComponent("x.md"))

        #expect(repo.rootCallCount == 1, "symlink 表記のディレクトリで rev-parse が再実行されている")
        #expect(repo.trackedCallCount == 1, "symlink 表記のルートで追跡ファイルが再列挙されている")
    }

    @Test("warm はバックグラウンドでキャッシュを温める", testTimeLimit())
    func warmPopulatesCacheInBackground() async {
        let repo = FakeRepository(
            root: .root(url("/repo")),
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
        _ = sut.trackedFileIndex(forFileAt: url("/repo/docs/x.md"))
        #expect(repo.trackedCallCount == 1)
    }
}
