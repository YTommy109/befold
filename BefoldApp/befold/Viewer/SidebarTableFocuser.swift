import AppKit

/// サイドバーの List を裏打ちする `NSTableView` への操作(フォーカス要求とスクロール追従)を
/// 担う型(TASK-443)。
///
/// `FileListModel` から分けているのは、これがモデルの状態ではなく **AppKit のビュー操作**
/// だから。参照は `@ObservationIgnored`(= 観測対象ではない)であり、`FileListModel` が
/// `import AppKit` していた唯一の理由でもあった。
///
/// `@Observable` にしない。ここに載る値は画面へ出るものではなく、観測させると
/// 行描画のたびに設定される `tableView` の代入が再描画を誘発する。
@MainActor
final class SidebarTableFocuser {
    /// サイドバー行から見つかった `NSTableView` への弱参照。
    /// `SidebarTableViewLocator` が行描画時に設定する。クリック時に first responder へ
    /// 昇格させるためだけの UI 専用値(#144)。
    weak var tableView: NSTableView?

    /// サイドバーの `NSTableView` を first responder にする。選択ハイライトを青にし(#144)、
    /// サイドバーを開いた直後からフォルダー名がアクティブ(黒)表示になり矢印キーで
    /// 操作できるようにする(task-118)。
    ///
    /// 参照がまだ解決していない場合は、次のランループで数回だけ再試行する。サイドバーを
    /// 畳んだ状態から初めて開いた直後は、List の行(と `NSTableView` 参照)の生成が
    /// フォーカス要求に間に合わないことがあるため。
    func focus(retriesRemaining: Int = 5) {
        guard let tableView, let window = tableView.window else {
            guard retriesRemaining > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.focus(retriesRemaining: retriesRemaining - 1)
            }
            return
        }
        window.makeFirstResponder(tableView)
    }

    /// `row` を可視領域へ入れる。行番号の決め方(いま見えている一覧の何番目か)は
    /// 呼び出し元が持ち、ここは遅延と `NSTableView` 呼び出しだけを担う。
    ///
    /// 一覧の差し替えより先に選択を書く経路(選択復元)があるため、`NSTableView` が新しい行を
    /// 反映したあとになるよう次のランループへ遅らせる(固定待ちは不要)。行番号は遅延後に
    /// 決めさせる——遅延前に確定させると、その間に一覧が入れ替わったとき別の行へスクロールする。
    /// 行がまだ無ければ(選択復元・ツリー復元で一覧の到着が選択より遅れる形 / TASK-481)、
    /// 要求を保持して `retryPendingScroll()` からの再試行に備える。可視化できた時点で
    /// 要求は消える(残すと以後の一覧差し替えのたびに選択行へ引き戻される)。
    func scrollIntoView(row: @escaping @MainActor () -> Int?) {
        pendingScroll = row
        attemptPendingScroll()
    }

    /// 一覧の差し替え後に呼ぶ(`FileListModel.setEntries`)。まだ行を見つけられていない
    /// スクロール要求があれば、新しい一覧で再試行する。
    func retryPendingScroll() {
        guard pendingScroll != nil else { return }
        attemptPendingScroll()
    }

    /// 直近のスクロール要求の行番号クロージャ。行が見つかるまで保持する。
    /// 新しい要求が来たら上書きされ、古い要求は破棄される(開始時の無効化)。
    private var pendingScroll: (@MainActor () -> Int?)?

    private func attemptPendingScroll() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let row = pendingScroll?() else { return }
            pendingScroll = nil
            tableView?.scrollRowToVisible(row)
        }
    }
}
