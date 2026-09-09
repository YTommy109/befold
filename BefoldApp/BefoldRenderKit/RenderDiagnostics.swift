import Foundation

/// 描画面の準備完了が**永久に来ない**形の障害を切り分けるための診断ログ(TASK-607)。
///
/// この経路の故障はどれも「黙って止まる」ため、症状が
/// 「`ViewerReadinessGate.isReady` が false のまま」としてしか出ない。原因になりうる
/// 分岐が複数あり（バンドル欠落・遮断ポリシーの完了が来ない・ナビゲーションの
/// キャンセル・WebContent プロセスの終了）、どれも同じ症状に畳まれる。
/// 分岐ごとに通過を記録して、CI のログから**どこで止まったか**を読めるようにする。
///
/// 既定では何もしない。`BEFOLD_RENDER_DIAGNOSTICS=1` のときだけ書く。
/// `os.Logger` ではなく `NSLog` を使うのは、`swift test` の出力（= CI のログ）へ
/// 出したいため——Logger は `log stream` でしか拾えない。
enum RenderDiagnostics {
    static let isEnabled = ProcessInfo.processInfo.environment["BEFOLD_RENDER_DIAGNOSTICS"] == "1"

    /// 有効なときだけメッセージを stderr へ書く。無効なら文字列の組み立ても行わない。
    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        NSLog("[befold-render] %@", message())
    }
}
