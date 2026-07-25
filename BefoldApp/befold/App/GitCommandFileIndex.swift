import BefoldKit
import Foundation

/// GitRepository を使って追跡ファイル一覧を返し、リポジトリルート単位でキャッシュする。
/// キャッシュは .git/index の fingerprint で無効化するため、外部のブランチ/ワークツリー
/// 切替・commit で追跡集合が変わっても自動で再取得する。git 管理外は nil。
/// 参照は少数(開いているウィンドウ分)のため、単一 NSLock で直列化する
/// (subprocess を lock 内で回すが、fingerprint 一致時はキャッシュ命中で subprocess 無し)。
/// キャッシュ未命中時は lock 内で `git` subprocess を待つため、ウィンドウを多数開いている
/// と呼び出しが直列化し、1 つの遅い `git ls-files` が他ウィンドウの fingerprint チェックを
/// ブロックしうる。
final class GitCommandFileIndex: GitFileIndexing, @unchecked Sendable {
    private let repository: GitRepositoryReading
    private let lock = NSLock()
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
