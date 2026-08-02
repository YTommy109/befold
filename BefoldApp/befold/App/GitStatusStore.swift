import BefoldKit
import Foundation

/// 状態取得の結果。バッジ描画用のマップと、更新契機に使う `.git/index` の実パスを返す。
struct GitStatusResult: Equatable, Sendable {
    var statuses: [String: GitFileStatus] = [:]
    /// 監視すべき `.git/index` のパス。git 管理外・取得失敗時は nil。
    var indexURL: URL?

    static let empty = GitStatusResult()
}

/// 状態を取り直す条件。
enum GitStatusRefreshPolicy: Sendable {
    /// 常に取り直す。作業ツリーの編集は `.git/index` を動かさないため、
    /// ユーザー操作・表示中ファイルの保存を契機にする場合はこちら。
    case always
    /// `.git/index` の fingerprint が前回取得時から変わっているときだけ取り直す。
    /// `.git` 配下の書き込み(index 以外の一時ファイル等)で無駄に git を起こさないための門番。
    case onlyIfIndexChanged
}

/// リポジトリルート単位で `GitStatusSnapshot` をキャッシュし、全ウィンドウで共有する。
///
/// 先例は `WorktreeCatalog`(@MainActor キャッシュ + `Task.detached` で git 実行 +
/// 結果だけをメインアクターへ反映)。`GitCommandFileIndex` の `NSLock` 直列化は踏襲しない。
/// メインアクター上でロックを握って subprocess を待つ形になり噛み合わないため。
/// 同一ルートへの要求が重なった場合は実行中のタスクへ相乗りして git の重複起動を畳む。
@MainActor
@Observable
final class GitStatusStore {
    /// ルートの正規化パスキー → 直近のスナップショット。
    private var cache: [String: GitStatusSnapshot] = [:]
    /// 実行中の取得タスク。同じルートへの要求はここへ相乗りする。
    @ObservationIgnored
    private var inFlight: [String: Task<GitStatusSnapshot?, Never>] = [:]
    /// git 状態の取得元。テストは実 subprocess を避けるため差し替える。
    @ObservationIgnored
    private let reader: any GitStatusReading
    /// ディレクトリが属するリポジトリの作業ツリールートを解決する。
    ///
    /// 本番では全ウィンドウ共有の `gitFileIndex` を渡す(Store が独自に `GitRepository` を
    /// 生成して rev-parse を重ねない、というリポジトリ規約に従う)。既定は常に nil を返す
    /// 無効化実装で、注入し忘れたテストが git を起動しないことを保証する。
    @ObservationIgnored
    private let resolveRepositoryRoot: @Sendable (URL) -> URL?

    init(
        reader: any GitStatusReading = GitStatusReader(),
        resolveRepositoryRoot: @escaping @Sendable (URL) -> URL? = { _ in nil }
    ) {
        self.reader = reader
        self.resolveRepositoryRoot = resolveRepositoryRoot
    }

    /// directory が属するリポジトリの状態を取得する。git 管理外・取得失敗なら空を返す。
    ///
    /// ルート解決と git 実行はどちらもメインアクターの外で行い、結果だけを戻す。
    /// 呼び出し側(SidebarNavigator)は世代ガードで古い結果を捨てる。
    func statuses(
        forDirectoryAt directory: URL, policy: GitStatusRefreshPolicy = .always
    ) async -> GitStatusResult {
        let resolveRepositoryRoot = resolveRepositoryRoot
        guard let root = await Task.detached(priority: .utility, operation: {
            resolveRepositoryRoot(directory)
        }).value else { return .empty }
        // index が動いていないなら git を起こす理由がない。`.git` 配下への index 以外の
        // 書き込み(参照更新・一時ファイル)で status を連打しないための門番。
        if let reusable = await cachedResultIfIndexUnchanged(at: root, policy: policy) {
            return reusable
        }
        guard let snapshot = await snapshot(forRepositoryAt: root) else { return .empty }
        return GitStatusResult(statuses: snapshot.statuses, indexURL: snapshot.indexURL)
    }

    /// `.onlyIfIndexChanged` かつ前回取得時から `.git/index` が動いていなければ、
    /// キャッシュ済みの結果を返す(= git を起こさない)。それ以外は nil を返して取得へ進む。
    /// fingerprint の取得は stat 1 回だけだが、ネットワークボリュームでも詰まらないよう
    /// 他の git 呼び出しと同じくメインアクターの外で行う。
    private func cachedResultIfIndexUnchanged(
        at root: URL, policy: GitStatusRefreshPolicy
    ) async -> GitStatusResult? {
        guard policy == .onlyIfIndexChanged, let cached = cache[root.normalizedPathKey] else {
            return nil
        }
        let reader = reader
        let current = await Task.detached(priority: .utility) {
            reader.indexFingerprint(forRepositoryAt: root)
        }.value
        guard current == cached.indexFingerprint else { return nil }
        return GitStatusResult(statuses: cached.statuses, indexURL: cached.indexURL)
    }

    /// ルート単位のスナップショットを取り直す。取得できなければ(git を動かせなければ)nil。
    private func snapshot(forRepositoryAt root: URL) async -> GitStatusSnapshot? {
        let key = root.normalizedPathKey
        if let running = inFlight[key] { return await running.value }
        let reader = reader
        let task = Task<GitStatusSnapshot?, Never> {
            await Task.detached(priority: .utility) { reader.status(forRepositoryAt: root) }.value
        }
        inFlight[key] = task
        let snapshot = await task.value
        inFlight[key] = nil
        // `.unavailable` 相当(nil)はキャッシュしない。答えが不明なだけであり、
        // キャッシュすると一時的な失敗で機能が固まったまま復帰しなくなる。
        if let snapshot { cache[key] = snapshot }
        return snapshot ?? cache[key]
    }

    /// 既に取得済みのスナップショット(あれば)。Phase 2 でのキャッシュ妥当性判定に使う。
    func cachedSnapshot(forRepositoryRoot root: URL) -> GitStatusSnapshot? {
        cache[root.normalizedPathKey]
    }
}
