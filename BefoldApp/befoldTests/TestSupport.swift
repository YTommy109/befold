import BefoldTestSupport
import Foundation
import Testing

/// FileWatcher の監視準備完了（file source の kevent 登録）を条件ベースで確認する。
///
/// `DispatchSource.resume()` は同期的に戻るが、kevent のカーネル登録は dispatch の
/// マネージャスレッドで**非同期**に完了する。そのため `FileWatcher.init` 直後は
/// `.delete` / `.rename` のような一度きり（エッジトリガー）のイベントを取りこぼしうる。
/// `.write` は再試行で救済できるが、削除・rename は再実行できないため、非冪等な操作を
/// 行う前にこのプローブで登録完了を観測しておく。
///
/// 手順:
/// 1. 対象ファイルへ書き込みを繰り返し、最初のコールバック到達を待って file source の
///    登録完了を観測する。`atomically: false`（in-place 書き込み）を使うのは、
///    `atomically: true` が rename 経由で監視を張り直し登録レースを再発させるため。
/// 2. プローブ書き込みのデバウンス残コールバックが後続の検証を汚さないよう、
///    コールバック数が `quiescePeriod` の間ひとつも増えなくなるまで待つ。
///
/// - Parameter quiescePeriod: 静穏判定の待機時間。既定 0.15s はテスト用 debounce 0.05s の
///   3 倍で、DebouncerTests の settlePeriod(= delay * 3)と同じ基準。
///   最後のプローブ書き込みのデバウンス発火を十分に取り込める。
/// - Returns: 静穏化後のコールバック回数。以降は「操作後の発火」を
///   この基準値との比較（`callbackCount.get() > baseline`）で判定する。
/// `confirmWatcherArmed` の静穏化待ちを打ち切る秒数。
///
/// 他のポーリング待機と同じ単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)から導く。
/// 独自の固定値にすると、thread-sanitizer ジョブのように CI 側で予算を延長した環境で、
/// 待てば成功するケースを打ち切って赤にしてしまう。
/// 環境変数がなければ従来どおり `quiescePeriod` の 20 倍。
func quiesceCutoffSeconds(quiescePeriod: TimeInterval) -> TimeInterval {
    testTimeoutSeconds(fallback: quiescePeriod * 20)
}

func confirmWatcherArmed(
    file: URL,
    callbackCount: LockedBox<Int>,
    quiescePeriod: TimeInterval = 0.15,
    sourceLocation: SourceLocation = #_sourceLocation
) async -> Int {
    // arm 自体が失敗したらこの時点で失敗が記録される（waitUntilWithRetry が報告する）。
    await waitUntilWithRetry(sourceLocation: sourceLocation, action: {
        try? "arm-probe-\(Int.random(in: 0 ... 999))"
            .write(to: file, atomically: false, encoding: .utf8)
    }, until: {
        callbackCount.get() > 0
    })

    // 静穏化を待つ。コールバックが延々と入り続ける状況で無限ループしないよう、
    // 打ち切り期限を設ける(期限の導出は quiesceCutoffSeconds 参照)。
    let deadline = Date().addingTimeInterval(quiesceCutoffSeconds(quiescePeriod: quiescePeriod))
    var last = callbackCount.get()
    while Date() < deadline {
        try? await Task.sleep(for: .seconds(quiescePeriod))
        let current = callbackCount.get()
        if current == last { return current }
        last = current
    }
    Issue.record(
        "confirmWatcherArmed がコールバックの静穏化を待ちきれなかった",
        sourceLocation: sourceLocation
    )
    return callbackCount.get()
}
