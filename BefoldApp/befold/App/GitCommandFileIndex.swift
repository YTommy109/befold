import BefoldKit
import Foundation

/// GitRepository を使って追跡ファイル一覧を返し、リポジトリルート単位でキャッシュする。
/// キャッシュは .git/index の fingerprint で無効化するため、外部のブランチ/ワークツリー
/// 切替・commit で追跡集合が変わっても自動で再取得する。git 管理外は nil。
/// 本番では ViewerWindowManager が持つ単一インスタンスを全ウィンドウで共有する。
/// 同じリポジトリを開く N ウィンドウで `git ls-files` の実行と追跡ファイル一覧の実体を
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
    /// 追跡ファイル一覧を保持しておくリポジトリ数の上限。
    /// このインスタンスはアプリ寿命で生きるため、上限が無いと開いたことのある全リポジトリの
    /// [URL] を抱え続ける(10 万ファイルのモノレポなら 1 つで数十 MB)。
    /// 実際に行き来するリポジトリは同時に数個なので、LRU で古い方から捨てる。
    static let maxCachedRoots = 4

    private let repository: GitRepositoryReading
    private let lock = NSLock()
    /// ディレクトリ → リポジトリルート。entryByRoot と違い意図的に無効化しない。
    /// そのため寿命の間、`git init` でリポジトリになった/リポジトリでなくなったディレクトリは
    /// 古い答えを返し続ける。無効化には毎回 `rev-parse` の subprocess が要る一方、
    /// 表示中の文書のリポジトリ所属が入れ替わるのは稀なため、この staleness を受け入れる。
    private var rootByDir: [String: URL?] = [:]
    private var entryByRoot: [String: (fingerprint: Date?, files: [URL])] = [:]
    /// entryByRoot のキーを最近使った順(先頭が直近)に並べたもの。LRU の追い出しに使う。
    private var rootsByRecency: [String] = []

    init(repository: GitRepositoryReading = GitRepository()) {
        self.repository = repository
    }

    func trackedFiles(forFileAt url: URL) -> [URL]? {
        let dirKey = url.deletingLastPathComponent().standardizedFileURL.path

        lock.lock(); defer { lock.unlock() }

        let root: URL?
        if let cached = rootByDir[dirKey] {
            root = cached
        } else {
            root = repository.root(forFileAt: url)
            rootByDir[dirKey] = root
        }
        guard let root else { return nil }

        let fingerprint = repository.indexFingerprint(at: root)
        if let entry = entryByRoot[root.path], entry.fingerprint == fingerprint {
            touch(root.path)
            return entry.files
        }
        let files = repository.trackedFiles(at: root)
        entryByRoot[root.path] = (fingerprint, files)
        touch(root.path)
        return files
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
    func warm(forFileAt url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.trackedFiles(forFileAt: url)
        }
    }
}
