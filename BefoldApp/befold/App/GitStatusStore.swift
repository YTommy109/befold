import BefoldKit
import Foundation

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
    func statuses(forDirectoryAt directory: URL) async -> [String: GitFileStatus] {
        let resolveRepositoryRoot = resolveRepositoryRoot
        guard let root = await Task.detached(priority: .utility, operation: {
            resolveRepositoryRoot(directory)
        }).value else { return [:] }
        return await snapshot(forRepositoryAt: root)?.statuses ?? [:]
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
