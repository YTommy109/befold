import BefoldKit
import Foundation

/// サイドバーの git 状態(バッジ・変更ファイル絞り込みの材料)の取得と反映を担う型
/// (TASK-442.4)。
///
/// **この型は `fileListModel` の git 状態だけを書く**(`applyGitStatus` 経由)。基準
/// ディレクトリは `SidebarBaseDirectoryResolver`、行は `SidebarTreePresenter`、
/// 選択・カレントディレクトリは `SidebarNavigator` が書く。同じ `FileListModel` を
/// 4 つの型が書くが、属性が重ならないことが唯一の正当化根拠なので、この分割表を崩さないこと。
///
/// **発行順序(sequence)の採番はこの型の内側だけで行う。** 以前は
/// `SidebarNavigator.gitStatusGeneration` を単発取得・一覧との結合取得・一括無効化の
/// 3 箇所が進めていた。採番点を 1 つに閉じることがこの分割の実質的な利得で、
/// 採番済みの値は `StatusRequest` の `fileprivate` として運ぶため外からは読めない。
/// そのため `StatusRequest` は**このファイルから出さないこと**(Swift の `fileprivate` は
/// ファイルスコープなので、別ファイルへ移した時点でこの保証が消える)。
///
/// 反映の可否判定(recency + ディレクトリ対付け)はここではなく
/// `FileListModel.applyGitStatus(_:for:sequence:)` が一括で行う(ADR 0003)。
@MainActor
final class SidebarGitStatusCoordinator {
    /// git 状態の反映先。
    private let fileListModel: FileListModel
    /// git の読み取り。使うのは `statuses(forDirectoryAt:policy:)` だけ。
    private let git: any SidebarGitReading
    /// `.git/index` を監視するウォッチャの生成器。既定は実 FileWatcher。
    /// テストは実ファイルシステム監視を避けるため差し替える。
    private let makeGitIndexWatcher: GitIndexWatch.WatcherFactory
    /// `.git/index` の監視。対象パスの管理は GitIndexWatch が持つ。
    /// init で self を渡せないため、attach 前の最初の取得までに解決できるよう遅延で作る。
    private lazy var gitIndexWatch = GitIndexWatch(makeWatcher: makeGitIndexWatcher) { [weak self] in
        self?.refresh(policy: .onlyIfIndexChanged)
    }

    /// 取得タスクの発行順序の採番器。一覧取得・基準ディレクトリ解決とは完了タイミングが
    /// 独立する(subprocess の所要時間が別)ため、別の番号で発行する。
    /// 反映の可否判定(recency ガード)は持たず、採番だけを担う(ADR 0003)。
    private var sequence = 0
    /// 直近に発行した取得タスク。テストから完了を待つために公開する。
    ///
    /// **ここに載るのは常に git 取得のタスクだけ。** 絞り込み ON のときの反映は一覧取得
    /// タスクの中で起きるので、その完了を待ちたいテストは
    /// `SidebarNavigator.pendingListingTask` を待つこと(ON では一覧と git を同一
    /// メインアクター実行で反映するのが不変条件そのもの / TASK-293)。一覧タスクを
    /// ここへ載せ替えると、この型の doc が嘘になる。
    private(set) var pendingTask: Task<Void, Never>?

    /// 反映の通知先。循環参照を避けるため weak。
    ///
    /// クロージャ注入にしない。`gitStatusDidApply()` は「バッジと表示中ファイルの差分の
    /// 更新契機を 1 つにする」判断をコンパイル時に守らせるための必須メソッド(TASK-330)で、
    /// クロージャを 1 段挟むとその意図が薄まる。
    private weak var host: SidebarNavigatorHost?

    init(
        fileListModel: FileListModel,
        git: any SidebarGitReading,
        makeGitIndexWatcher: @escaping GitIndexWatch.WatcherFactory
    ) {
        self.fileListModel = fileListModel
        self.git = git
        self.makeGitIndexWatcher = makeGitIndexWatcher
    }

    /// 通知先を接続する。SidebarNavigator.attach(to:) が中継する
    /// (host は ViewerWindowController の super.init 後にしか渡せない)。
    func attach(to host: SidebarNavigatorHost) {
        self.host = host
    }

    // MARK: - Single Refresh

    /// git 状態を取り直して反映する。取得(ルート解決 + git 実行)はメイン外で行う。
    /// 機能が無効なら注入クロージャが常に空を返すため git は起動しない。
    /// - Parameter policy: `.onlyIfIndexChanged` は `.git/index` が動いていないとき git を
    ///   起こさない(`.git` 配下の書き込み通知が契機のとき用)。それ以外では `.always`。
    func refresh(policy: GitStatusRefreshPolicy = .always) {
        let request = beginRequest(for: fileListModel.currentDirectory, policy: policy)
        pendingTask = Task {
            let result = await Self.awaitingCancellable(request.task)
            self.apply(result, for: request)
        }
    }

    // MARK: - Listing-Coupled Refresh

    /// 一覧取得と対にする取得を開始し、券を返す。呼び出し側は列挙の**前に**これを呼ぶこと
    /// (取得と列挙をどちらも先に起こしておけば、待ち時間は直列にならず遅いほうに揃う)。
    ///
    /// 券を受け取った側は次のどちらかを行う。
    /// - 絞り込み ON: `awaitResult(_:)` で待ってから `apply(_:for:)` で反映する
    /// - 絞り込み OFF: `applyWhenReady(_:)` に任せる(一覧と切り離して遅れて反映される)
    func beginListingRequest(for directory: URL) -> StatusRequest {
        beginRequest(for: directory, policy: .always)
    }

    /// 券の結果を待つ。待ち側のキャンセル(ウィンドウを閉じたとき)を取得側へも伝えるため、
    /// 素の `await task.value` ではなくこちらを通す。
    ///
    /// **`apply(_:for:)` と融合して 1 本にしていないのは、呼び出し側が待ちと反映の間に
    /// 一覧世代・host 生存のガードを挟むため**(TASK-294)。API を 1 本減らすために
    /// このガードの位置を動かすと、一覧世代が古いときでも git 結果が
    /// `FileListModel.applyGitStatus` まで届く形に変わる。
    func awaitResult(_ request: StatusRequest) async -> GitStatusResult {
        await Self.awaitingCancellable(request.task)
    }

    /// 取得した git 状態を FileListModel へ渡す。反映の可否(発行順序・ディレクトリ対付け)は
    /// FileListModel.applyGitStatus が一括判定する(ADR 0003)。受け付けられたときだけ
    /// index の監視対象を合わせる(古い結果で監視を張り直してはならない)。
    func apply(_ result: GitStatusResult, for request: StatusRequest) {
        let accepted = fileListModel.applyGitStatus(
            SidebarGitStatus(result: result), for: request.directory, sequence: request.sequence
        )
        guard accepted else { return }
        gitIndexWatch.update(indexURL: result.indexURL)
        // バッジが動いたら、同じ契機で表示中ファイルの差分も取り直す。
        // 捨てられた(accepted == false)のは「より新しい結果が既に反映済み」のときだけで、
        // その結果自身がここを通っているため取り残しは起きない。
        host?.gitStatusDidApply()
    }

    /// 券の結果を一覧と切り離して反映する(絞り込み OFF の経路)。
    /// 一覧より遅れて着地しても FileListModel の保留機構が一覧と突き合わせるため、
    /// 先着後着どちらでも整合は崩れない(TASK-297)。
    func applyWhenReady(_ request: StatusRequest) {
        pendingTask = Task {
            let result = await Self.awaitingCancellable(request.task)
            self.apply(result, for: request)
        }
    }

    // MARK: - Cancellation

    /// 進行中の取得を破棄する。ウィンドウを閉じるときに呼ぶ。
    /// キャンセルは協調的で、走り出した subprocess は完了して結果を返しうる。番号を進めて
    /// おかないとその結果が反映ガードを通り抜け、閉じたウィンドウのために `.git/index`
    /// 監視を張り直す(以後リポジトリを触るたび git が起動し続ける / TASK-300)。
    func cancelPending() {
        sequence += 1
        // 反映済み sequence を発行済みの先頭へ揃えることで、進行中の取得を一括で無効化する
        // (FileListModel 側で「反映済みより新しい」ものだけを通すため / ADR 0003, 元 TASK-299)。
        fileListModel.invalidatePendingGitStatus(upTo: sequence)
        pendingTask?.cancel()
        pendingTask = nil
        gitIndexWatch.stop()
    }

    // MARK: - Request

    /// 取得 1 回を識別する券。発行時点の sequence と取得タスクを持つ。
    ///
    /// `sequence` を `fileprivate` に閉じることで、採番がこの型の外へ漏れないことを
    /// 型で守る。**このファイルの外へ移さないこと**(`fileprivate` はファイルスコープ)。
    struct StatusRequest {
        let directory: URL
        fileprivate let sequence: Int
        fileprivate let task: Task<GitStatusResult, Never>
    }

    private func beginRequest(
        for directory: URL, policy: GitStatusRefreshPolicy
    ) -> StatusRequest {
        sequence += 1
        return StatusRequest(
            directory: directory,
            sequence: sequence,
            task: Task { await self.git.statuses(forDirectoryAt: directory, policy: policy) }
        )
    }

    private static func awaitingCancellable(
        _ task: Task<GitStatusResult, Never>
    ) async -> GitStatusResult {
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
