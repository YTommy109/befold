import Foundation

/// 表示中ファイルの差分取得をメインアクターの外へ逃がし、重複要求を畳む。
///
/// `GitStatusStore` と違い**結果をキャッシュしない**。作業ツリーの編集は `.git/index` を
/// 動かさないため、あちらの fingerprint による無効化がここでは効かず、
/// 「保存したのに古い差分が出続ける」形で必ず陳腐化する。畳み込みだけを行い、
/// 同じ要求が重なったときに git を二重起動しないことに責務を絞る。
@MainActor
final class GitDiffLoader {
    private let reader: any GitDiffReading
    /// 実行中の取得タスク。同じ (ルート, ファイル) への要求はここへ相乗りする。
    private var inFlight: [String: Task<GitFileDiff?, Never>] = [:]

    init(reader: any GitDiffReading = GitDiffReader()) {
        self.reader = reader
    }

    /// - Returns: 取得結果。git を動かせなかった場合は nil。
    func diff(forFileAt url: URL, in root: URL) async -> GitFileDiff? {
        let key = "\(root.normalizedPathKey)\u{0}\(url.normalizedPathKey)"
        if let running = inFlight[key] { return await running.value }

        let reader = reader
        let task = Task.detached(priority: .utility) { reader.diff(forFileAt: url, in: root) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}
