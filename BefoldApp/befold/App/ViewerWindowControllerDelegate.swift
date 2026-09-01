import Foundation

/// ViewerWindowController のウィンドウイベント(クローズ・rename・キー化など)を
/// 上位のウィンドウ管理層へ通知するプロトコル。ViewerWindowManager が実装する。
///
/// **表示モードの変更は通知しない。** 表示モードは「文書の状態」であり、窓が生きている間は
/// その窓のライブ値が有効で、窓間の同期は行わない(ADR 0002「複数ウィンドウでの扱い」)。
/// TASK-371 でここにあった didChangeDisplayMode は TASK-388 で撤去した。
@MainActor
protocol ViewerWindowControllerDelegate: AnyObject {
    func viewerWindowWillClose(_ controller: ViewerWindowController)
    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController)
    func viewerWindow(_ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL)
    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    )
    /// 差分レイアウトが切り替わったことを伝える。
    ///
    /// レイアウトはアプリ全体で 1 個を共有する設定(`DiffDisplayPreference`)で、
    /// モード切替セグメントの差分アイコンがその値を映す。ツールバーは view ベースで
    /// validate を通らないため(ADR 0002)、操作した窓を含む全窓を再同期する必要がある。
    func viewerWindowDidToggleDiffLayout(_ controller: ViewerWindowController)

    /// ユーザーがウィンドウをリサイズし終えたことを伝える。
    ///
    /// 寸法は**アプリ全体で 1 個**の「次に開く窓の出発点」として保存する(TASK-583)。
    /// 窓自身がストアを持たないのは、粒度がアプリ全体だから——窓ごとに書き込み先を
    /// 持たせると、どの窓の値が残るかが窓の寿命に左右される。
    func viewerWindow(_ controller: ViewerWindowController, didAdjustFrameTo descriptor: String)
}

/// performFileSwitch の結果。呼び出し元(明示的なファイル選択と履歴ナビゲーション)が
/// 成否で扱いを分けられるよう、単なる Bool ではなく理由を返す。
enum FileSwitchOutcome {
    /// 切替が完了した。
    case switched
    /// 対象ファイルが見つからず切替できなかった(利用者へは警告済み)。
    case failed
}
