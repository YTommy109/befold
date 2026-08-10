import BefoldKit
import Foundation

/// GitRepository を使って追跡ファイルの照合索引を返し、リポジトリルート単位でキャッシュする。
/// 列挙結果ではなく索引をキャッシュするのは、索引の構築が候補数に比例した正規化コストを持ち、
/// 解決バッチのたびに作り直すと大きなリポジトリで無視できない時間になるため。
/// キャッシュは .git/index の fingerprint で無効化するため、外部のブランチ/ワークツリー
/// 切替・commit で追跡集合が変わっても自動で再取得する。git 管理外は nil。
/// 本番では ViewerWindowManager が持つ単一インスタンスを全ウィンドウで共有する。
/// 同じリポジトリを開く N ウィンドウで索引の構築と実体を 1 つに畳むため。
///
/// ロックは目的ごとに 3 つに分ける。索引の構築を待つ間に握るのは
/// **キーごとのロック(`dirLocks` / `rootLocks`)だけ**で、キャッシュ本体を守る
/// `stateLock` は辞書の読み書きの間しか握らない。こうしないと 1 つの遅いリポジトリの
/// 走査が無関係なリポジトリのウィンドウまでブロックする。キーごとに分けることで、
/// 共有の狙いである「同一リポジトリでの構築の重複排除」は保ったまま、
/// 別リポジトリ同士は互いに待たない。
final class GitCommandFileIndex: GitFileIndexing, @unchecked Sendable {
    /// 追跡ファイル索引を保持しておくリポジトリ数の上限。
    /// このインスタンスはアプリ寿命で生きるため、上限が無いと開いたことのある全リポジトリの
    /// 索引を抱え続ける(索引は候補ごとに構成要素の配列を持つため、生の [URL] より数倍重い)。
    /// 実際に行き来するリポジトリは同時に数個なので、LRU で古い方から捨てる。
    static let maxCachedRoots = 4

    private let repository: GitRepositoryReading
    /// キャッシュ本体(rootByDir / entryByRoot / rootsByRecency)だけを守る。
    /// このロックを握ったまま `git` subprocess を待ってはならない。
    private let stateLock = NSLock()
    /// ディレクトリキーごとの相互排他。同じディレクトリの `rev-parse` を 1 度に畳む。
    private let dirLocks = KeyedLock()
    /// ルートキーごとの相互排他。同じリポジトリの fingerprint / 列挙 / 索引構築を 1 度に畳む。
    /// `dirLocks` と別インスタンスにするのは、ルート直下のファイルでは dirKey と rootKey が
    /// 同じ値になりうるため(同一 registry だと自己デッドロックする)。
    private let rootLocks = KeyedLock()
    /// ディレクトリ → リポジトリルート。entryByRoot と違い意図的に無効化しない。
    /// そのため寿命の間、`git init` でリポジトリになった/リポジトリでなくなったディレクトリは
    /// 古い答えを返し続ける。無効化には毎回 `rev-parse` の subprocess が要る一方、
    /// 表示中の文書のリポジトリ所属が入れ替わるのは稀なため、この staleness を受け入れる。
    /// entryByRoot と違い件数の上限も設けない。1 件はパス文字列 2 本ぶんで、
    /// 抱えるのは「開いたことのあるディレクトリの数」に留まるため、
    /// 追い出しの複雑さに見合わない。
    private var rootByDir: [String: GitRootLookup] = [:]
    private var entryByRoot: [String: (fingerprint: Date?, index: SuffixPathIndex)] = [:]
    /// entryByRoot のキーを最近使った順(先頭が直近)に並べたもの。LRU の追い出しに使う。
    private var rootsByRecency: [String] = []

    init(repository: GitRepositoryReading = GitRepository()) {
        self.repository = repository
    }

    func repositoryRoot(forFileAt url: URL) -> URL? {
        resolvedRoot(forFileAt: url)
    }

    func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
        // ルート解決の中で握るディレクトリキーのロックは、ここへ戻る時点で解放済み。
        // ルートキーのロックを入れ子で取らないことでロック順序の問題自体を無くす。
        guard let root = resolvedRoot(forFileAt: url) else { return nil }

        // root は rev-parse 由来だが、GitRepositoryReading の契約は正規化を保証しない。
        // dirKey と同じ規約のキーに揃え、別表記の root が別エントリに割れないようにする。
        let rootKey = root.normalizedPathKey
        // このリポジトリの列挙を 1 つに畳む。別リポジトリの呼び出しは別キーなので待たない。
        return rootLocks.withLock(rootKey) {
            let fingerprint = repository.indexFingerprint(at: root)
            if let entry = cachedEntry(forRootKey: rootKey), entry.fingerprint == fingerprint {
                touchLocking(rootKey)
                return entry.index
            }
            guard let files = repository.trackedFiles(at: root) else {
                // 列挙できなかった。空の索引を今の fingerprint で覚えると、次に commit などで
                // index が動くまでこのリポジトリのリンク化が丸ごと止まる。覚えずに次回やり直し、
                // 手元に前回の索引があるならそれを返してリンクを生かしておく。
                if let stale = cachedEntry(forRootKey: rootKey) {
                    touchLocking(rootKey)
                    return stale.index
                }
                return nil
            }
            // 索引の構築も列挙と同じくルートキーのロック内で行う。候補数に比例した正規化コストが
            // あるため、ここで作って共有しないと解決バッチのたびに全ウィンドウが作り直すことになる。
            let index = SuffixPathIndex(candidates: files)
            stateLock.lock()
            entryByRoot[rootKey] = (fingerprint, index)
            touch(rootKey)
            stateLock.unlock()
            return index
        }
    }

    /// url を含むリポジトリの作業ツリールート。git 管理外・判定不能なら nil。
    /// ディレクトリ単位で結果をキャッシュするため、同じファイル(や同ディレクトリの別ファイル)への
    /// `repositoryRoot` と `trackedFileIndex` は rev-parse を 1 度しか払わない。
    private func resolvedRoot(forFileAt url: URL) -> URL? {
        let dirKey = url.deletingLastPathComponent().normalizedPathKey
        if let cached = cachedLookup(forDirKey: dirKey) { return cached.foundRoot }

        return dirLocks.withLock(dirKey) {
            // ロックを待っている間に別の呼び出しが解決を終えているかもしれない。
            // ここで見直さないと、待っていた人数ぶん rev-parse が重複する。
            if let cached = cachedLookup(forDirKey: dirKey) { return cached.foundRoot }

            let lookup = repository.root(forFileAt: url)
            // 確定した答えだけを覚える。git を実行できなかっただけの結果を覚えると、
            // 一時的な失敗がアプリ寿命の間「git 管理外」として固定されてしまう。
            if lookup != .undetermined {
                stateLock.lock()
                rootByDir[dirKey] = lookup
                stateLock.unlock()
            }
            return lookup.foundRoot
        }
    }

    private func cachedLookup(forDirKey dirKey: String) -> GitRootLookup? {
        stateLock.lock(); defer { stateLock.unlock() }
        return rootByDir[dirKey]
    }

    private func cachedEntry(forRootKey rootKey: String) -> (fingerprint: Date?, index: SuffixPathIndex)? {
        stateLock.lock(); defer { stateLock.unlock() }
        return entryByRoot[rootKey]
    }

    private func touchLocking(_ rootPath: String) {
        stateLock.lock(); defer { stateLock.unlock() }
        touch(rootPath)
    }

    /// root を最近使ったものとして記録し、上限を超えた分を古い方から捨てる。
    /// stateLock を保持した状態で呼ぶこと。
    private func touch(_ rootPath: String) {
        if let existing = rootsByRecency.firstIndex(of: rootPath) {
            rootsByRecency.remove(at: existing)
        }
        rootsByRecency.insert(rootPath, at: 0)
        while rootsByRecency.count > Self.maxCachedRoots {
            entryByRoot.removeValue(forKey: rootsByRecency.removeLast())
        }
    }

    /// 開いた/切り替えたタイミングで背景実行し、解決要求時のキャッシュ命中を狙う。
    /// 多重呼び出し(タブの連続切替など)は抑止しないが、同じルートへ重なった場合は
    /// `rootLocks` が直列化するため `git` の実行自体は 1 度に畳まれる。
    func warm(forFileAt url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.trackedFileIndex(forFileAt: url)
        }
    }
}

/// キーごとに相互排他を与える。異なるキーの呼び出しは互いに待たない。
///
/// `git` subprocess を待つ区間を「同じリポジトリ(同じディレクトリ)を見ている呼び出し同士」
/// だけに絞るために使う。単一のロックで全体を守ると、遅い 1 リポジトリが無関係な
/// リポジトリの呼び出しまで止めてしまう。
///
/// 使用中のキーだけを登録に残す(待ち人数を数え、0 になったら削除する)。残し続けると、
/// 開いたことのある全ディレクトリぶんの `NSLock` をアプリ寿命の間抱えることになる。
private final class KeyedLock: @unchecked Sendable {
    private let registryLock = NSLock()
    private var entries: [String: (lock: NSLock, users: Int)] = [:]

    func withLock<T>(_ key: String, _ body: () -> T) -> T {
        let lock = acquire(key)
        defer { release(key, lock) }
        return body()
    }

    private func acquire(_ key: String) -> NSLock {
        registryLock.lock()
        let lock: NSLock
        if var entry = entries[key] {
            lock = entry.lock
            entry.users += 1
            entries[key] = entry
        } else {
            lock = NSLock()
            entries[key] = (lock, 1)
        }
        registryLock.unlock()
        // 登録を守るロックは手放してから待つ。ここを握ったまま待つと、
        // キーを分けた意味が無くなる(別キーの acquire も止まる)。
        lock.lock()
        return lock
    }

    private func release(_ key: String, _ lock: NSLock) {
        lock.unlock()
        registryLock.lock()
        if var entry = entries[key] {
            entry.users -= 1
            if entry.users == 0 {
                entries.removeValue(forKey: key)
            } else {
                entries[key] = entry
            }
        }
        registryLock.unlock()
    }
}
