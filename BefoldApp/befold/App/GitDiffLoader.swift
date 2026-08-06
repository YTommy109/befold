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
///
/// 要求の順番(`Ticket`)は**契機の時点で**呼び出し側が取る。取得の直前に取ると、
/// 同じファイル変更イベントから出た兄弟要求(複数ウィンドウ)が、先行ウィンドウの
/// 取得開始より後の要求として扱われて合流できず、窓の数だけ git が起動する
/// (リポジトリルート解決の await を挟むぶん到着がずれるため = TASK-325)。
///
/// 全ウィンドウで 1 個を共有すること。窓ごとに持つと畳み込みが窓の中でしか効かない。
/// 生成は ViewerWindowManager に集約してあり、ここを破ると
/// `ViewerWindowControllerDiffTests.openViewerSharesDiffLoader` が落ちる。
@MainActor
final class GitDiffLoader {
    /// 要求の順番。契機の時点で発行し、取得へ持ち回る。
    /// 生成を `takeTicket()` に限ることで、呼び出し側が数値を組み立てられないようにする。
    struct Ticket {
        let value: Int
    }

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

    /// 要求の順番を発行する。**取得を起こす契機の時点で**呼ぶこと(ファイル変更の検知直後など)。
    /// リポジトリルート解決などの await を挟んだ後に取ると、同じ契機の兄弟要求どうしが
    /// 合流できなくなる。
    func takeRequestTicket() -> Ticket {
        Ticket(value: takeTicket())
    }

    /// - Parameter requestedAt: `takeRequestTicket()` で契機の時点に取った順番。
    /// - Returns: 取得結果。git を動かせなかった場合は nil。
    func diff(forFileAt url: URL, in root: URL, requestedAt requestTicket: Ticket) async -> GitFileDiff? {
        let key = "\(root.normalizedPathKey)\u{0}\(url.normalizedPathKey)"

        while let running = inFlight[key] {
            // 自分より後に始まった取得なら、読んでいるツリーは自分の要求以降。相乗りしてよい。
            if running.ticket > requestTicket.value { return await running.task.value }
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
