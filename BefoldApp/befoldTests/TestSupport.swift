import BefoldTestSupport
import Foundation

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
/// - Parameter quiescePeriod: 静穏判定の待機時間。既定 0.3s はテスト用 debounce 0.05s の
///   6 倍で、最後のプローブ書き込みのデバウンス発火を十分に取り込める。
/// - Returns: 静穏化後のコールバック回数。以降は「操作後の発火」を
///   この基準値との比較（`callbackCount.get() > baseline`）で判定する。
func confirmWatcherArmed(
    file: URL,
    callbackCount: LockedBox<Int>,
    quiescePeriod: TimeInterval = 0.3
) async -> Int {
    await waitUntilWithRetry(action: {
        try? "arm-probe-\(Int.random(in: 0 ... 999))"
            .write(to: file, atomically: false, encoding: .utf8)
    }, until: {
        callbackCount.get() > 0
    })
    var last = callbackCount.get()
    while true {
        try? await Task.sleep(for: .seconds(quiescePeriod))
        let current = callbackCount.get()
        if current == last { return current }
        last = current
    }
}
