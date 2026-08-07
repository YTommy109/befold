import Foundation

/// 表示中ファイルの差分取得をメインアクターの外へ逃がし、重複要求を畳む。
///
/// `GitStatusStore` と違い**結果をキャッシュしない**。作業ツリーの編集は `.git/index` を
/// 動かさないため、あちらの fingerprint による無効化がここでは効かず、
/// 「保存したのに古い差分が出続ける」形で必ず陳腐化する。畳み込みだけを行い、
/// 同じ要求が重なったときに git を二重起動しないことに責務を絞る。
///
/// ## 合流の判定
///
/// 畳み込みは**まだ作業ツリーを読み始めていない取得にだけ**相乗りする。読み始めた後の
/// 取得は要求より前のツリーを見ているため、そこへ相乗りすると変更前の差分が返り、
/// 再取得の契機も無いまま表示が固まる(キャッシュしない理由と同じ「保存したのに
/// 古い差分が出る」が、合流を経由して起きる形 = TASK-321)。
///
/// この判定は**時間ではなく順序**で決まる。`diff(forFileAt:resolvingRootWith:)` は同期で、
/// 呼んだその場でバッチへ登録する。バッチを閉じるのは取得タスク本体の先頭、つまり
/// ツリーを読み始める直前であり、それは登録したターンより後になることが保証される。
/// したがって同じ契機(1 回のファイル変更イベントを全ウィンドウへ配る 1 ターン)から
/// 出た兄弟要求は、**どの順で実行されても**必ず 1 回の取得に合流する。
///
/// 走行中かどうかで合流を決めてはならない。負荷でメインアクターが詰まると、先行の
/// 取得が完走してから兄弟要求が動き出すことがあり、完了済みの取得には相乗りできず
/// 窓の数だけ git が起動する(TASK-346。TSan 付きの全体実行で実際に発生した)。
///
/// ## 呼び出し側の契約
///
/// - **契機の時点で同期に呼ぶこと。** リポジトリルートの解決などを await した後に
///   呼ぶと、同じ契機の兄弟要求どうしが別ターンに散り、合流できなくなる。
///   ルート解決はこのクラスが取得タスクの中で行う(引数のクロージャ)。
/// - 走行中の取得の管理はファイルの正規化パスだけをキーにする。**同じファイルには
///   常に同じリポジトリルートが対応すること**を前提にしている(本番ではルートを
///   ファイルの所在ディレクトリから解決しており、`GitCommandFileIndex` が
///   無効化しないキャッシュを持つため一意)。ルートをファイル以外から決める
///   呼び出し元を足す場合は、キーにルートを戻すこと。
/// - 全ウィンドウで 1 個を共有すること。窓ごとに持つと畳み込みが窓の中でしか効かない。
///   生成は ViewerWindowManager に集約してあり、ここを破ると
///   `ViewerWindowManagerDiffTests.openViewerSharesDiffLoader` が落ちる。
@MainActor
final class GitDiffLoader {
    /// 1 回の取得と、それに相乗りしている要求のまとまり。
    private struct Batch {
        /// 登録を受け付けている間だけ true。ツリーを読み始める直前に false になる。
        var isAcceptingRequests: Bool
        /// 世代。登録が後続のバッチへ置き換わった後に、古いバッチが
        /// 自分ではない登録を書き換えてしまわないよう識別に使う。
        let generation: Int
        let task: Task<GitFileDiff?, Never>
    }

    private let reader: any GitDiffReading
    /// ファイルごとの直近のバッチ。
    private var batches: [String: Batch] = [:]
    private var nextGeneration = 0

    init(reader: any GitDiffReading = GitDiffReader()) {
        self.reader = reader
    }

    /// 差分を取得する。**取得を起こす契機の時点で同期に**呼ぶこと。
    ///
    /// - Parameters:
    ///   - url: 差分を見たいファイル。
    ///   - resolveRoot: リポジトリルートの解決。メインアクターの外で呼ばれる。
    ///     nil を返した場合は取得せず nil を返す。
    /// - Returns: 取得結果を待てるタスク。同じ契機の兄弟要求には同じタスクを返す。
    @discardableResult
    func diff(
        forFileAt url: URL,
        resolvingRootWith resolveRoot: @escaping @Sendable () -> URL?
    ) -> Task<GitFileDiff?, Never> {
        let key = url.normalizedPathKey
        if let batch = batches[key], batch.isAcceptingRequests { return batch.task }
        return start(key: key, url: url, resolveRoot: resolveRoot)
    }

    /// 新しいバッチを開始して登録する。
    ///
    /// 直前のバッチがまだ走行中なら、その完了を待ってから読む。git を同じファイルに
    /// 対して二重に走らせないためで、待った結果はより新しいツリーのものになる。
    private func start(
        key: String,
        url: URL,
        resolveRoot: @escaping @Sendable () -> URL?
    ) -> Task<GitFileDiff?, Never> {
        let reader = reader
        let generation = nextGeneration
        nextGeneration += 1
        // 相乗りできないと判定した相手。走行中なら追い越さない。
        let previous = batches[key]?.task
        let task = Task { @MainActor [weak self] in
            // 契機のターンは終わった。ここから先に届く要求は別の契機なので、
            // これから読むツリーを共有させてよい相手ではない。読み始める前に閉じる。
            self?.closeBatch(key: key, generation: generation)
            if let previous { _ = await previous.value }
            let result = await Task.detached(priority: .utility) {
                guard let root = resolveRoot() else { return nil as GitFileDiff? }
                return reader.diff(forFileAt: url, in: root)
            }.value
            self?.forgetBatch(key: key, generation: generation)
            return result
        }
        batches[key] = Batch(isAcceptingRequests: true, generation: generation, task: task)
        return task
    }

    /// 自分の世代の登録だけを閉じる。後続が既に別のバッチを登録していることがある。
    private func closeBatch(key: String, generation: Int) {
        guard batches[key]?.generation == generation else { return }
        batches[key]?.isAcceptingRequests = false
    }

    /// 自分の世代の登録だけを取り下げる。
    private func forgetBatch(key: String, generation: Int) {
        guard batches[key]?.generation == generation else { return }
        batches[key] = nil
    }
}
