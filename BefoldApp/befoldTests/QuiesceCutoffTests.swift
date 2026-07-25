import BefoldTestSupport
import Foundation
import Testing

/// `confirmWatcherArmed` の静穏化カットオフが、他のポーリング待機と同じ
/// 単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)に連動することをピン留めする。
///
/// 環境変数はプロセス起動時に決まるため、テストからは書き換えず「現在の環境で
/// `testTimeoutSeconds` と一致するか」を検証する。カットオフが固定値へ退行すると、
/// 環境変数を設定している CI ジョブ(通常 30 秒 / thread-sanitizer 120 秒)でこのテストが落ちる。
@Suite
struct QuiesceCutoffTests {
    @Test("静穏化カットオフが BEFOLD_TEST_TIMEOUT_SECONDS と連動する")
    func cutoffFollowsTestTimeoutBudget() {
        #expect(quiesceCutoffSeconds(quiescePeriod: 0.3) == testTimeoutSeconds(fallback: 6))
        #expect(quiesceCutoffSeconds(quiescePeriod: 1) == testTimeoutSeconds(fallback: 20))
    }

    /// 環境変数を設定している CI ジョブでは前提が成立しないため、未設定の環境でのみ実行する。
    @Test(
        "環境変数がなければ従来どおり quiescePeriod の 20 倍になる",
        .enabled(if: ProcessInfo.processInfo.environment["BEFOLD_TEST_TIMEOUT_SECONDS"] == nil)
    )
    func cutoffFallsBackToTwentyTimesQuiescePeriod() {
        #expect(quiesceCutoffSeconds(quiescePeriod: 0.3) == 6)
    }
}
