import Foundation

/// 表示中ファイルの差分取得をメインアクターの外へ逃がし、重複要求を畳む。
///
/// `GitStatusStore` と違い**結果をキャッシュしない**。作業ツリーの編集は `.git/index` を
/// 動かさないため、あちらの fingerprint による無効化がここでは効かず、
/// 「保存したのに古い差分が出続ける」形で必ず陳腐化する。畳み込みだけを行い、
/// 同じ要求が重なったときに git を二重起動しないことに責務を絞る。
///
/// 畳み込みは**自分の要求より後に開始した取得にだけ**相乗りする。走行中の取得は
/// 要求より前の作業ツリーを読んでいるため、そこへ相乗りすると変更前の差分が返り、
/// 再取得の契機も無いまま表示が固まる(キャッシュしない理由と同じ「保存したのに
/// 古い差分が出る」が、合流を経由して起きる形)。
@MainActor
final class GitDiffLoader {
    /// 走行中の取得。`ticket` は取得を開始した順番で、要求の到着順と突き合わせて
    /// 「その結果が要求より新しいか」を判定するために持つ。
    private struct Running {
        let ticket: Int
        let task: Task<GitFileDiff?, Never>
    }

    private let reader: any GitDiffReading
    /// (ルート, ファイル) ごとの走行中の取得。
    private var inFlight: [String: Running] = [:]
    /// 要求の到着と取得の開始に順番を振る単調増加カウンタ。
    private var nextTicket = 0

    init(reader: any GitDiffReading = GitDiffReader()) {
        self.reader = reader
    }

    /// - Returns: 取得結果。git を動かせなかった場合は nil。
    func diff(forFileAt url: URL, in root: URL) async -> GitFileDiff? {
        let key = "\(root.normalizedPathKey)\u{0}\(url.normalizedPathKey)"
        let requestTicket = takeTicket()

        while let running = inFlight[key] {
            // 自分より後に始まった取得なら、読んでいるツリーは自分の要求以降。相乗りしてよい。
            if running.ticket > requestTicket { return await running.task.value }
            // 自分より前に始まった取得は結果が古い。終わるのを待ってから取り直す。
            // 走行中の登録は完了前に自分で取り下げるため(start 参照)、ここへ戻ってきた
            // 時点で同じ登録が残り続けることはない。
            _ = await running.task.value
        }
        return await start(key: key, url: url, in: root).value
    }

    /// 取得を開始して登録する。登録の取り下げは**タスク自身が完了前に**行う。
    /// 開始側が `await` から戻ってから取り下げる形にすると、先に起きた待機側が
    /// 完了済みの登録を見つけて待ち直し続け、開始側へ実行が渡らなくなる。
    private func start(key: String, url: URL, in root: URL) -> Task<GitFileDiff?, Never> {
        let reader = reader
        let ticket = takeTicket()
        let task = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                reader.diff(forFileAt: url, in: root)
            }.value
            // 後続が既に別の取得を登録していることがあるため、自分の登録だけ取り下げる。
            if self?.inFlight[key]?.ticket == ticket { self?.inFlight[key] = nil }
            return result
        }
        inFlight[key] = Running(ticket: ticket, task: task)
        return task
    }

    private func takeTicket() -> Int {
        defer { nextTicket += 1 }
        return nextTicket
    }
}
