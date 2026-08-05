import BefoldKit
import Foundation

/// `.git/index` の監視。add / commit / checkout など index を動かす操作を検知する。
///
/// 監視対象は git 状態を取得して初めて判明するため、取得のたびに `update(indexURL:)` を
/// 呼び、**対象パスが変わったときだけ**張り直す。毎回張り直すと DispatchSource の
/// 生成・破棄をディレクトリ移動のたびに繰り返すことになる。
///
/// index そのものだけでなく、その親(`.git` ディレクトリ)への書き込みでも通知が来る
/// (`FileWatcher` はアトミック保存に追従するため親ディレクトリも見ている)。
/// 通知の受け手が `.onlyIfIndexChanged` で問い合わせることで、`.git` 配下の無関係な
/// 書き込みでは git を起こさない。
@MainActor
final class GitIndexWatch {
    /// ウォッチャの生成器の型。GitIndexWatch 自身と、それを保持する SidebarNavigator の
    /// 両方で直書きされていたクロージャ型を 1 箇所へまとめる(TASK-298)。
    typealias WatcherFactory = (URL, @escaping @MainActor @Sendable () -> Void) -> FileWatching

    private let makeWatcher: WatcherFactory
    private let onChange: @MainActor @Sendable () -> Void
    private var watcher: FileWatching?
    /// 現在監視中のパス。同じパスへの張り直しを避ける判定に使う。
    private var watchedPath: String?

    init(
        makeWatcher: @escaping WatcherFactory,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        self.makeWatcher = makeWatcher
        self.onChange = onChange
    }

    /// 監視を最新の対象へ合わせる。`nil`(git 管理外)なら監視を止める。
    func update(indexURL: URL?) {
        guard let indexURL else { return stop() }
        let path = indexURL.normalizedPathKey
        guard path != watchedPath else { return }
        watcher?.stop()
        watchedPath = path
        watcher = makeWatcher(indexURL, onChange)
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        watchedPath = nil
    }
}
