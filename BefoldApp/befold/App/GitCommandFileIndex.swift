import BefoldKit
import Foundation

/// GitRepository を使って追跡ファイルの照合索引を返し、リポジトリルート単位でキャッシュする。
/// 列挙結果ではなく索引をキャッシュするのは、索引の構築が候補数に比例した正規化コストを持ち、
/// 解決バッチのたびに作り直すと大きなリポジトリで無視できない時間になるため。
/// キャッシュは .git/index の fingerprint で無効化するため、外部のブランチ/ワークツリー
/// 切替・commit で追跡集合が変わっても自動で再取得する。git 管理外は nil。
/// 本番では ViewerWindowManager が持つ単一インスタンスを全ウィンドウで共有する。
/// 同じリポジトリを開く N ウィンドウで `git ls-files` の実行と索引の実体を
/// 1 つに畳むためで、その代償として呼び出しは単一 NSLock で直列化される。
/// キャッシュ未命中時は lock 内で `git` subprocess を待つため、1 つの遅い `git ls-files` が
/// 他ウィンドウの fingerprint チェックをブロックしうる。この待ちが「共有しなければ各ウィンドウが
/// 自前で払っていたコストと同じ」と言えるのは同一リポジトリを開いている場合だけで、
/// **別リポジトリのウィンドウ間では共有前より悪化する**(リポジトリ A の列挙を待つ間、
/// リポジトリ B の呼び出しも止まる)。それでもここを共有するのは、呼び出し元が
/// MainActor 外で解決する(ViewerWindowController.resolveReferences)ため、この直列化が
/// 待たせるのはバックグラウンドのパス解決だけで UI は止まらないから。
/// `git` 自体がハングした場合は GitCommandRunner のタイムアウトが待ちを打ち切る。
final class GitCommandFileIndex: GitFileIndexing, @unchecked Sendable {
    /// 追跡ファイル索引を保持しておくリポジトリ数の上限。
    /// このインスタンスはアプリ寿命で生きるため、上限が無いと開いたことのある全リポジトリの
    /// 索引を抱え続ける(索引は候補ごとに構成要素の配列を持つため、生の [URL] より数倍重い)。
    /// 実際に行き来するリポジトリは同時に数個なので、LRU で古い方から捨てる。
    static let maxCachedRoots = 4

    private let repository: GitRepositoryReading
    private let lock = NSLock()
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

    func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
        let dirKey = url.deletingLastPathComponent().normalizedPathKey

        lock.lock(); defer { lock.unlock() }

        let lookup: GitRootLookup
        if let cached = rootByDir[dirKey] {
            lookup = cached
        } else {
            lookup = repository.root(forFileAt: url)
            // 確定した答えだけを覚える。git を実行できなかっただけの結果を覚えると、
            // 一時的な失敗がアプリ寿命の間「git 管理外」として固定されてしまう。
            if lookup != .undetermined { rootByDir[dirKey] = lookup }
        }
        guard case let .root(root) = lookup else { return nil }

        // root は rev-parse 由来だが、GitRepositoryReading の契約は正規化を保証しない。
        // dirKey と同じ規約のキーに揃え、別表記の root が別エントリに割れないようにする。
        let rootKey = root.normalizedPathKey
        let fingerprint = repository.indexFingerprint(at: root)
        if let entry = entryByRoot[rootKey], entry.fingerprint == fingerprint {
            touch(rootKey)
            return entry.index
        }
        guard let files = repository.trackedFiles(at: root) else {
            // 列挙できなかった。空の索引を今の fingerprint で覚えると、次に commit などで
            // index が動くまでこのリポジトリのリンク化が丸ごと止まる。覚えずに次回やり直し、
            // 手元に前回の索引があるならそれを返してリンクを生かしておく。
            if let stale = entryByRoot[rootKey] {
                touch(rootKey)
                return stale.index
            }
            return nil
        }
        // 索引の構築も列挙と同じくロック内で行う。候補数に比例した正規化コストがあるため、
        // ここで作って共有しないと解決バッチのたびに全ウィンドウが作り直すことになる。
        let index = SuffixPathIndex(candidates: files)
        entryByRoot[rootKey] = (fingerprint, index)
        touch(rootKey)
        return index
    }

    /// root を最近使ったものとして記録し、上限を超えた分を古い方から捨てる。
    /// lock を保持した状態で呼ぶこと。
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
    /// 多重呼び出し(タブの連続切替など)は抑止しない。2 回目以降はキャッシュ命中で
    /// ロックを取ってすぐ抜けるため、in-flight 管理を足すほどの重複コストにならない。
    func warm(forFileAt url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.trackedFileIndex(forFileAt: url)
        }
    }
}
