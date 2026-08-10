import BefoldKit
import Foundation

// MARK: - Diff Presentation

/// ソース表示へ重ねる git 差分の**取得と反映**を受け持つ。
///
/// 差分を「出すかどうか」は表示モード(`+Presentation`)の担当、
/// 「切り替えるコマンド」はメニューアクション(`+MenuActions`)の担当で、
/// ここに置くのは非同期取得とその世代管理(開始時に捨てる / 着地時に一致確認する)だけ。
@MainActor
extension ViewerWindowController {
    /// 表示中ファイルの差分を取り直して store へ反映する。
    ///
    /// 取得は非同期のため、戻ってきた時点で表示対象が変わっていないかを URL で確認する
    /// (遅れて着地した結果が現在の表示を壊すのを防ぐ)。切替時に古い差分を捨てる側は
    /// `ViewerStore.openFile` が担う(着地時の確認だけでは切替直後の残留を防げない)。
    ///
    /// リポジトリルートの解決はクロージャで `GitDiffLoader` へ渡し、差分取得と同じ
    /// detached タスクの中で行わせる。キャッシュに無いディレクトリではリポジトリを開いて
    /// 走査するため、メインアクター上で同期に呼ぶとコンテンツ再読込のたびに
    /// UI が止まりうる(遅いボリュームでは特に)。
    /// ここで解決を待ってからローダーを呼ぶ形へ戻すと、登録が契機のターンから外れて
    /// 兄弟要求が合流できなくなる(TASK-346)。
    /// 差分を出せない種別(画像・PDF・文書を出していない状態)では差分取得を起こさない。
    /// 表示側(ViewerContentView)が捨てるだけでは、契機の数だけ取得が走る。
    func refreshDiff() {
        guard let loader = diffLoader, isDiffShown, capabilities.canSelectDiffMode else {
            store.diffText = nil
            return
        }
        let url = fileURL
        let directory = url.deletingLastPathComponent()
        let index = gitFileIndex
        // 取得の登録は契機のここで**同期に**行う。await を挟んだ後に登録すると、同じ
        // ファイル変更イベントから出た他ウィンドウの要求が別のターンへ散り、合流できずに
        // 窓の数だけ git が起動する(TASK-325 / TASK-346)。ルート解決はローダーが
        // 取得タスクの中(メインアクターの外)で行う。
        let fetch = loader.diff(forFileAt: url) { index.repositoryRoot(forDirectoryAt: directory) }
        Task { @MainActor [weak self] in
            let result = await fetch.value
            // 取得中に OFF へ切り替わっていたら書き戻さない。表示は ViewerContentView の
            // ゲートで隠れるが、store.diffText に古い本文が残ると次に ON にした瞬間だけ
            // 取り直し前の差分が見える。
            guard let self, fileURL == url, isDiffShown else { return }
            store.diffText = Self.displayableDiff(result)
        }
    }

    /// 取得結果のうち、差分として描けるのは本文があるものだけ。
    /// それ以外(未追跡・バイナリ・変更なし・大きすぎる・取得できない)は nil にして
    /// 通常のソース表示へ戻す。理由ごとの表示分けは行わない(TASK-315 の次段)。
    static func displayableDiff(_ result: GitFileDiff?) -> String? {
        guard case let .diff(text) = result else { return nil }
        return text
    }

    /// 差分表示モードかどうか(メニューのチェック表示に使う)。
    ///
    /// 表示モード(ファイル単位のユーザー選択)であり、ビルドゲートの
    /// `FeatureGate.isSourceDiffEnabled` とは別物。
    /// 同名にすると無修飾参照でどちらにも解決しうるため、名前を分けている(TASK-323)。
    var isDiffShown: Bool {
        store.showsDiff
    }

    /// 差分レイアウトが左右分割かどうか(メニューのチェック表示に使う)。
    var isDiffLayoutSideBySide: Bool {
        diffDisplayPreference.layout == .sideBySide
    }
}
