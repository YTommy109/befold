import BefoldKit
import Foundation

/// GitRepository を使って追跡ファイル一覧を返し、リポジトリルート単位でキャッシュする。
/// キャッシュは .git/index の fingerprint で無効化するため、外部のブランチ/ワークツリー
/// 切替・commit で追跡集合が変わっても自動で再取得する。git 管理外は nil。
/// 本番では ViewerWindowManager が持つ単一インスタンスを全ウィンドウで共有する。
/// 同じリポジトリを開く N ウィンドウで `git ls-files` の実行と追跡ファイル一覧の実体を
/// 1 つに畳むためで、その代償として呼び出しは単一 NSLock で直列化される。
/// キャッシュ未命中時は lock 内で `git` subprocess を待つため、1 つの遅い `git ls-files` が
/// 他ウィンドウの fingerprint チェックをブロックしうる。ただしその待ち時間は、共有しなければ
/// 各ウィンドウが自前で払っていた列挙コストと同じものなので、全体では悪化しない
/// (fingerprint 一致時はキャッシュ命中で subprocess 無し)。
final class GitCommandFileIndex: GitFileIndexing, @unchecked Sendable {
    private let repository: GitRepositoryReading
    private let lock = NSLock()
    /// ディレクトリ → リポジトリルート。entryByRoot と違い意図的に無効化しない。
    /// そのため寿命の間、`git init` でリポジトリになった/リポジトリでなくなったディレクトリは
    /// 古い答えを返し続ける。無効化には毎回 `rev-parse` の subprocess が要る一方、
    /// 表示中の文書のリポジトリ所属が入れ替わるのは稀なため、この staleness を受け入れる。
    private var rootByDir: [String: URL?] = [:]
    private var entryByRoot: [String: (fingerprint: Date?, files: [URL])] = [:]

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
            return entry.files
        }
        let files = repository.trackedFiles(at: root)
        entryByRoot[root.path] = (fingerprint, files)
        return files
    }

    /// 開いた/切り替えたタイミングで背景実行し、解決要求時のキャッシュ命中を狙う。
    func warm(forFileAt url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.trackedFiles(forFileAt: url)
        }
    }
}
